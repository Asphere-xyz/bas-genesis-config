// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "./Injector.sol";

abstract contract Staking is IParlia, IStaking {

    uint32 public constant MISDEMEANOR_THRESHOLD = 50;
    uint32 public constant FELONY_THRESHOLD = 150;

    uint32 public constant DEFAULT_ACTIVE_VALIDATORS_LENGTH = 22;
    uint32 public constant DEFAULT_BLOCK_TIME_SEC = 3;
    uint32 public constant DEFAULT_EPOCH_BLOCK_INTERVAL = 100;
    /**
     * Frequency of reward distribution and validator refresh
     */
    uint32 public constant SLASH_AND_COMMIT_VALIDATOR_BLOCK_INTERVAL = 1 * 60 * 60 / DEFAULT_BLOCK_TIME_SEC; // 1 hour
    uint32 public constant DISTRIBUTE_DELEGATION_REWARDS_BLOCK_INTERVAL = 1 * 24 * 60 * 60 / DEFAULT_BLOCK_TIME_SEC; // 1 day
    uint32 public constant VALIDATOR_UNDELEGATE_LOCK_PERIOD = 7 * 24 * 60 * 60 / DEFAULT_BLOCK_TIME_SEC; // 7 days

    event ValidatorAdded(address validator);
    event ValidatorRemoved(address validator);
    event ValidatorSlashed(address validator, uint32 slashes);
    event Delegated(address validator, address staker, uint256 amount, uint64 epoch);
    event Undelegated(address validator, address staker, uint256 amount, uint64 epoch);

    enum ValidatorStatus {
        NotFound,
        Alive,
        Pending,
        Jail
    }

    struct ValidatorSnapshot {
        uint128 totalRewards;
        uint64 totalDelegated;
        uint32 slashesCount;
        // percents * 100 (ex. 0.3% = 0.3*100=30, min possible value is 0.01%, scale is 1e4)
        uint16 commissionRate;
    }

    struct Validator {
        address validatorAddress;
        address ownerAddress;
        ValidatorStatus status;
        uint64 changedAt;
        uint64 claimedAt;
    }

    struct DelegationOpDelegate {
        uint64 amount;
        uint64 epoch;
    }

    struct DelegationOpUndelegate {
        uint256 pendingAmount;
        uint64 afterBlock;
    }

    struct ValidatorDelegation {
        DelegationOpDelegate[] delegateQueue;
        uint64 delegateGap;
        DelegationOpUndelegate[] undelegateQueue;
        uint64 undelegateGap;
    }

    // mapping from validator address to validator
    mapping(address => Validator) internal _validatorsMap;
    // list of all validators that are in validators mapping
    address[] internal _validatorsList;
    // mapping with stakers to validators at epoch (validator -> delegator -> delegation)
    mapping(address => mapping(address => ValidatorDelegation)) internal _validatorDelegations;
    // mapping with validator snapshots per each epoch (validator -> epoch -> snapshot)
    mapping(address => mapping(uint64 => ValidatorSnapshot)) internal _validatorSnapshots;
    // consensus parameters
    uint32 internal _activeValidatorsLength;
    uint32 internal _epochBlockInterval;
    // total system fee that is available for claim for system needs
    uint256 internal _systemFee;

    constructor() {
        _activeValidatorsLength = DEFAULT_ACTIVE_VALIDATORS_LENGTH;
        _epochBlockInterval = DEFAULT_EPOCH_BLOCK_INTERVAL;
    }

    function getValidatorDelegation(address validatorAddress, address delegator) external view override returns (
        uint256 delegatedAmount,
        uint64 atEpoch
    ) {
        ValidatorDelegation memory delegation = _validatorDelegations[validatorAddress][delegator];
        if (delegation.delegateQueue.length == 0) {
            return (delegatedAmount = 0, atEpoch = 0);
        }
        DelegationOpDelegate memory snapshot = delegation.delegateQueue[delegation.delegateQueue.length - 1];
        return (delegatedAmount = snapshot.amount * 1 gwei, atEpoch = snapshot.epoch);
    }

    function getValidatorStatus(address validatorAddress) external view override returns (
        uint8 status,
        uint256 totalDelegated
    ) {
        Validator memory validator = _validatorsMap[validatorAddress];
        return (status = uint8(validator.status), totalDelegated = _totalDelegatedToValidator(validator));
    }

    function _totalDelegatedToValidator(Validator memory validator) internal view returns (uint256) {
        ValidatorSnapshot memory snapshot = _validatorSnapshots[validator.validatorAddress][validator.changedAt];
        return snapshot.totalDelegated * 1 gwei;
    }

    function delegate(address validatorAddress) payable external override {
        _delegateTo(msg.sender, validatorAddress, msg.value);
    }

    function undelegate(address validatorAddress, uint256 amount) payable external override {
        _undelegateFrom(msg.sender, validatorAddress, amount);
    }

    function _prevEpoch() internal view returns (uint64) {
        uint64 epoch = _currentEpoch();
        if (epoch > 0) epoch--;
        return epoch;
    }

    function _currentEpoch() internal view returns (uint64) {
        return uint64(block.number / _epochBlockInterval + 0);
    }

    function _nextEpoch() internal view returns (uint64) {
        return _currentEpoch() + 1;
    }

    function _touchValidatorSnapshot(Validator memory validator, uint64 epoch) internal returns (ValidatorSnapshot storage) {
        ValidatorSnapshot storage snapshot = _validatorSnapshots[validator.validatorAddress][epoch];
        // if snapshot is already initialized then just return it
        if (snapshot.totalDelegated > 0) {
            return snapshot;
        }
        // find previous snapshot to copy parameters from it
        ValidatorSnapshot memory lastModifiedSnapshot = _validatorSnapshots[validator.validatorAddress][validator.changedAt];
        // last modified snapshot might store zero value, for first delegation it might happen and its not critical
        snapshot.totalDelegated = lastModifiedSnapshot.totalDelegated;
        snapshot.commissionRate = lastModifiedSnapshot.commissionRate;
        // we must save last affected epoch for this validator to be able to restore total delegated
        // amount in the future (check condition upper)
        validator.changedAt = epoch;
        return snapshot;
    }

    function _applyNewValidatorCommissionRate(Validator memory validator, uint16 newCommissionRate) internal {
        ValidatorSnapshot storage snapshot = _touchValidatorSnapshot(validator, _nextEpoch());
        snapshot.commissionRate = newCommissionRate;
    }

    function _delegateTo(address fromDelegator, address toValidator, uint256 amount) internal {
        // 1 ether is minimum delegate amount
        require(amount >= 1 ether, "Staking: amount too low");
        require(amount % 1 ether == 0, "Staking: amount shouldn't have a remainder");
        // make sure validator exists at least
        Validator memory validator = _validatorsMap[toValidator];
        require(validator.status != ValidatorStatus.NotFound, "Staking: validator not found");
        uint64 nextEpoch = _nextEpoch();
        // Lets upgrade next snapshot parameters:
        // + find snapshot for the next epoch after current block
        // + increase total delegated amount in the next epoch for this validator
        // + re-save validator because last affected epoch might change
        ValidatorSnapshot storage validatorSnapshot = _touchValidatorSnapshot(validator, _nextEpoch());
        validatorSnapshot.totalDelegated += uint64(amount / 1 gwei);
        _validatorsMap[toValidator] = validator;
        // if last pending delegate has the same next epoch then its safe to just increase total
        // staked amount because it can't affect current validator set, but otherwise we must create
        // new record in delegation queue with the last epoch (delegations are ordered by epoch)
        ValidatorDelegation storage delegation = _validatorDelegations[toValidator][fromDelegator];
        if (delegation.delegateQueue.length > 0) {
            DelegationOpDelegate storage recentDelegateOp = delegation.delegateQueue[delegation.delegateQueue.length - 1];
            // if we already have pending snapshot for the next epoch then just increase new amount,
            // otherwise create next pending snapshot. (tbh it can't be greater, but what we can do here instead?)
            if (recentDelegateOp.epoch >= nextEpoch) {
                recentDelegateOp.amount += uint64(amount / 1 gwei);
            } else {
                delegation.delegateQueue.push(DelegationOpDelegate({epoch : nextEpoch, amount : recentDelegateOp.amount + uint64(amount / 1 gwei)}));
            }
        } else {
            // there is no any delegations at al, lets create the first one
            delegation.delegateQueue.push(DelegationOpDelegate({epoch : nextEpoch, amount : uint64(amount / 1 gwei)}));
        }
        // emit event with the next epoch
        emit Delegated(toValidator, fromDelegator, amount, nextEpoch);
    }

    function _undelegateFrom(address toDelegator, address fromValidator, uint256 amount) internal {
        // 1 ether is minimum delegate amount
        require(amount >= 1 ether, "Staking: amount too low");
        require(amount % 1 ether == 0, "Staking: amount shouldn't have a remainder");
        // make sure validator exists at least
        Validator memory validator = _validatorsMap[fromValidator];
        require(validator.status != ValidatorStatus.NotFound, "Staking: validator not found");
        uint64 nextEpoch = _nextEpoch();
        // Lets upgrade next snapshot parameters:
        // + find snapshot for the next epoch after current block
        // + increase total delegated amount in the next epoch for this validator
        // + re-save validator because last affected epoch might change
        ValidatorSnapshot storage validatorSnapshot = _touchValidatorSnapshot(validator, nextEpoch);
        require(validatorSnapshot.totalDelegated >= uint64(amount / 1 gwei), "Staking: insufficient balance");
        validatorSnapshot.totalDelegated -= uint64(amount / 1 gwei);
        _validatorsMap[fromValidator] = validator;
        // if last pending delegate has the same next epoch then its safe to just increase total
        // staked amount because it can't affect current validator set, but otherwise we must create
        // new record in delegation queue with the last epoch (delegations are ordered by epoch)
        ValidatorDelegation storage delegation = _validatorDelegations[fromValidator][toDelegator];
        require(delegation.delegateQueue.length > 0, "Staking: delegation queue is empty");
        DelegationOpDelegate storage recentDelegateOp = delegation.delegateQueue[delegation.delegateQueue.length - 1];
        require(recentDelegateOp.amount >= uint64(amount / 1 gwei), "Staking: insufficient balance");
        uint64 nextDelegatedAmount = recentDelegateOp.amount - uint64(amount / 1 gwei);
        if (recentDelegateOp.epoch >= nextEpoch) {
            // decrease total delegated amount for the next epoch
            recentDelegateOp.amount = nextDelegatedAmount;
        } else {
            // there is no pending delegations, so lets create the new one with the new amount
            delegation.delegateQueue.push(DelegationOpDelegate({epoch : nextEpoch, amount : nextDelegatedAmount}));
        }
        // create new undelegate queue operation with soft lock
        uint64 claimableAfterBlock = uint64(block.number) + VALIDATOR_UNDELEGATE_LOCK_PERIOD;
        delegation.undelegateQueue.push(DelegationOpUndelegate({pendingAmount : amount, afterBlock : claimableAfterBlock}));
        // emit event with the next epoch number
        emit Undelegated(fromValidator, toDelegator, amount, nextEpoch);
    }

    function _claimDelegatorRewardsAndPendingUndelegates(address validator, address delegator) internal {
        ValidatorDelegation storage delegation = _validatorDelegations[validator][delegator];
        uint256 availableFunds = 0;
        uint64 currentEpoch = _currentEpoch();
        // process delegate queue to calculate staking rewards
        while (delegation.delegateGap < delegation.delegateQueue.length) {
            DelegationOpDelegate memory delegateOp = delegation.delegateQueue[delegation.delegateGap];
            uint256 voteChangedAtEpoch = 0;
            if (delegation.delegateGap < delegation.delegateQueue.length - 1) {
                voteChangedAtEpoch = delegation.delegateQueue[delegation.delegateGap + 1].epoch;
            }
            for (; delegateOp.epoch < currentEpoch && (voteChangedAtEpoch == 0 || delegateOp.epoch < voteChangedAtEpoch); delegateOp.epoch++) {
                ValidatorSnapshot memory validatorSnapshot = _validatorSnapshots[validator][delegateOp.epoch];
                if (validatorSnapshot.totalDelegated == 0) {
                    continue;
                }
                (uint256 delegatorFee, uint256 ownerFee) = _calcValidatorSnapshotEpochPayout(validatorSnapshot);
                availableFunds += delegatorFee * delegateOp.amount / validatorSnapshot.totalDelegated;
            }
            delete delegation.delegateQueue[delegation.delegateGap];
            ++delegation.delegateGap;
        }
        // process all items from undelegate queue
        for (; delegation.undelegateGap < delegation.undelegateQueue.length; delegation.undelegateGap++) {
            DelegationOpUndelegate memory undelegateOp = delegation.undelegateQueue[delegation.undelegateGap];
            if (block.number <= undelegateOp.afterBlock) {
                break;
            }
            availableFunds += undelegateOp.pendingAmount;
            delete delegation.undelegateQueue[delegation.undelegateGap];
        }
        // send available for claim funds to delegator
        address payable payableDelegator = payable(delegator);
        payableDelegator.transfer(availableFunds);
    }

    function _claimValidatorOwnerRewards(Validator storage validator) internal {
        uint64 currentEpoch = _currentEpoch();
        uint256 availableFunds = 0;
        for (; validator.claimedAt < currentEpoch; validator.claimedAt++) {
            ValidatorSnapshot memory validatorSnapshot = _validatorSnapshots[validator.validatorAddress][validator.claimedAt];
            (uint256 delegatorFee, uint256 ownerFee) = _calcValidatorSnapshotEpochPayout(validatorSnapshot);
            availableFunds += ownerFee;
        }
        address payable payableOwner = payable(validator.ownerAddress);
        payableOwner.transfer(availableFunds);
    }

    function _calcValidatorSnapshotEpochPayout(ValidatorSnapshot memory validatorSnapshot) internal pure returns (uint256 delegatorFee, uint256 ownerFee) {
        // ownerFee_(18+4-4=18) = totalRewards_18 * commissionRate_4 / 1e4
        ownerFee = validatorSnapshot.totalRewards * validatorSnapshot.commissionRate / 1e4;
        // delegatorRewards = totalRewards - ownerFee
        delegatorFee = validatorSnapshot.totalRewards - ownerFee;
    }

    function _addValidator(address account, address owner) internal {
        // don't allow to have different validators with same address
        require(_validatorsMap[account].status == ValidatorStatus.NotFound, "Staking: validator already exist");
        // init validator default params
        Validator memory validator = _validatorsMap[account];
        validator.validatorAddress = account;
        validator.ownerAddress = owner;
        validator.status = ValidatorStatus.Alive;
        _validatorsMap[account] = validator;
        // push initial validator snapshot at zero epoch with default params
        _validatorSnapshots[account][0] = ValidatorSnapshot({
        totalRewards : 0,
        totalDelegated : 0,
        slashesCount : 0,
        commissionRate : 0
        });
        // add new validator to array
        _validatorsList.push(account);
        // emit event
        emit ValidatorAdded(account);
    }

    function _removeValidator(address account) internal {
        require(_validatorsMap[account].status != ValidatorStatus.NotFound, "Staking: validator not found");
        // find index of validator in validator set
        int256 indexOf = - 1;
        for (uint256 i = 0; i < _validatorsList.length; i++) {
            if (_validatorsList[i] != account) continue;
            indexOf = int256(i);
            break;
        }
        require(indexOf >= 0, "Staking: validator not found");
        // remove validator from array
        if (_validatorsList.length > 1 && uint256(indexOf) != _validatorsList.length - 1) {
            _validatorsList[uint256(indexOf)] = _validatorsList[_validatorsList.length - 1];
        }
        _validatorsList.pop();
        // remove from validators map
        delete _validatorsMap[account];
        emit ValidatorRemoved(account);
    }

    function isValidatorAlive(address account) external override view returns (bool) {
        return _validatorsMap[account].status == ValidatorStatus.Alive;
    }

    function isValidator(address account) external override view returns (bool) {
        return _validatorsMap[account].status != ValidatorStatus.NotFound;
    }

    function getValidators() external view override returns (address[] memory) {
        address[] memory activeValidators;
        if (_validatorsList.length >= _activeValidatorsLength) {
            activeValidators = new address[](_activeValidatorsLength);
        } else {
            activeValidators = new address[](_validatorsList.length);
        }
        // sort validators
        address[] memory orderedValidators = new address[](_validatorsList.length);
        for (uint256 i = 0; i < _validatorsList.length; i++) {
            orderedValidators[i] = _validatorsList[i];
        }
        for (uint256 i = 0; i < orderedValidators.length; i++) {
            Validator memory left = _validatorsMap[orderedValidators[i]];
            for (uint256 j = i + 1; j < orderedValidators.length; j++) {
                Validator memory right = _validatorsMap[orderedValidators[j]];
                if (_totalDelegatedToValidator(left) < _totalDelegatedToValidator(right)) {
                    (orderedValidators[i], orderedValidators[j]) = (orderedValidators[j], orderedValidators[i]);
                }
            }
        }
        // form top 22 active validators
        for (uint256 i = 0; i < activeValidators.length; i++) {
            activeValidators[i] = orderedValidators[i];
        }
        return activeValidators;
    }

    function getSystemFee() external view override returns (uint256) {
        return _systemFee;
    }

    function _depositFee(address validatorAddress) internal {
        require(msg.value > 0, "Staking: deposit is zero");
        // make sure validator is active
        Validator memory validator = _validatorsMap[validatorAddress];
        require(validator.status == ValidatorStatus.Alive, "Staking: validator not active");
        // increase total pending rewards for validator for current epoch
        uint64 currentEpoch = uint64(block.number / _epochBlockInterval);
        ValidatorSnapshot memory currentSnapshot = _validatorSnapshots[validatorAddress][currentEpoch];
        currentSnapshot.totalRewards += uint128(msg.value);
        _validatorSnapshots[validatorAddress][currentEpoch] = currentSnapshot;
    }

    function claimDepositFee(address validatorAddress) external override {
        //        // make sure validator exists at least
        //        Validator memory validator = _validatorsMap[validatorAddress];
        //        require(validator.status != ValidatorStatus.NotFound, "Staking: validator not found");
        //        // only validator owner can claim deposit fee
        //        require(msg.sender == validator.validatorOwner, "Staking: only validator owner");
        //        // claim deposit fee
        //        _claimDepositFee(validator);
    }

    function _claimDepositFee(Validator memory validator) internal {
        //        // check that claimable fee is greater than 0
        //        uint256 totalFee = validator.confirmedBalance;
        //        require(totalFee > 0, "Staking: nothing to claim");
        //        // decrease confirmed balance
        //        validator.confirmedBalance -= totalFee;
        //        // send fee to the validator owner
        //        address payable payableOwner = payable(validator.validatorOwner);
        //        payableOwner.transfer(totalFee);
    }

    function _slashValidator(address validatorAddress) internal {
        // make sure validator was active
        Validator memory validator = _validatorsMap[validatorAddress];
        require(validator.status == ValidatorStatus.Alive, "Staking: validator not found");
        // increase slashes for current epoch
        uint64 currentEpoch = uint64(block.number / _epochBlockInterval);
        ValidatorSnapshot memory currentSnapshot = _validatorSnapshots[validatorAddress][currentEpoch];
        currentSnapshot.slashesCount++;
        _validatorSnapshots[validatorAddress][currentEpoch] = currentSnapshot;
        // emit event
        emit ValidatorSlashed(validatorAddress, currentSnapshot.slashesCount);
    }

    receive() external payable {
        _systemFee += msg.value;
    }
}
