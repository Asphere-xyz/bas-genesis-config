// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "./Injector.sol";

abstract contract Staking is IParlia, IStaking {

    uint32 public constant MISDEMEANOR_THRESHOLD = 50;
    uint32 public constant FELONY_THRESHOLD = 150;

    uint32 public constant DEFAULT_ACTIVE_VALIDATORS_SIZE = 22;
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
    event Delegated(address validator, address staker, uint256 amount);
    event Undelegated(address validator, address staker, uint256 amount);

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
        uint16 commissionRate;
    }

    struct Validator {
        address validatorAddress;
        address ownerAddress;
        ValidatorStatus status;
        uint64 changedAtEpoch;
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

    // stake
    // nextEpoch = block.number/100+1
    // if last(stakeQueue).epoch != nextEpoch then push else amount=newAmount
    uint32 internal _activeValidatorsSize;
    uint32 internal _epochBlockInterval;

    uint64 internal _recentRewardDistribution;
    uint64 internal _recentSlashAndRewardDistribution;
    uint256 internal _systemFee;

    constructor() {
        _activeValidatorsSize = DEFAULT_ACTIVE_VALIDATORS_SIZE;
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
        ValidatorSnapshot memory snapshot = _validatorSnapshots[validator.validatorAddress][validator.changedAtEpoch];
        return snapshot.totalDelegated * 1 gwei;
    }

    function delegate(address validatorAddress) payable external override {
        _delegateTo(msg.sender, validatorAddress, msg.value);
    }

    function undelegate(address validatorAddress, uint256 amount) payable external override {
        _undelegateFrom(msg.sender, validatorAddress, amount);
    }

    function currentEpoch() external view returns (uint64) {
        return uint64(block.number / _epochBlockInterval);
    }

    function getEpochLength() external view returns (uint64) {
        return uint64(_epochBlockInterval);
    }

    function nextEpoch() external view returns (uint64) {
        return uint64(block.number / _epochBlockInterval + 1);
    }

    function _delegateTo(address fromAddress, address toValidator, uint256 amount) internal {
        // 1 ether is minimum delegate amount
        require(amount >= 1 ether, "Staking: delegate amount too low");
        require(amount % 1 gwei == 0, "Staking: amount shouldn't have a remainder");
        // make sure validator exists at least
        Validator memory validator = _validatorsMap[toValidator];
        require(validator.status != ValidatorStatus.NotFound, "Staking: validator not found");
        // find snapshot for the next epoch after current block
        uint64 nextEpoch = uint64(block.number / _epochBlockInterval + 1);
        ValidatorSnapshot memory nextEpochSnapshot = _validatorSnapshots[toValidator][nextEpoch];
        // if total delegated amount is zero then we need to initialize new snapshot with
        // parameters from previous affected epoch
        if (nextEpochSnapshot.totalDelegated == 0) {
            ValidatorSnapshot memory lastModifiedSnapshot = _validatorSnapshots[toValidator][validator.changedAtEpoch];
            // last modified snapshot might store zero value, for first delegation it might happen and its not critical
            nextEpochSnapshot.totalDelegated = lastModifiedSnapshot.totalDelegated;
            nextEpochSnapshot.commissionRate = lastModifiedSnapshot.commissionRate;
            // we must save last affected epoch for this validator to be able to restore total delegated
            // amount in the future (check condition upper)
            validator.changedAtEpoch = nextEpoch;
            _validatorsMap[toValidator] = validator;
        }
        // increase total delegated amount in the next epoch for this validator
        nextEpochSnapshot.totalDelegated += uint64(amount / 1 gwei);
        // if last pending delegate has the same next epoch then its safe to just increase total
        // staked amount because it can't affect current validator set, but otherwise we must create
        // new record in delegation queue with the last epoch (delegations are ordered by epoch)
        ValidatorDelegation storage delegation = _validatorDelegations[toValidator][fromAddress];
        if (delegation.delegateQueue.length > 0) {
            DelegationOpDelegate storage lastPendingDelegate = delegation.delegateQueue[delegation.delegateQueue.length - 1];
            if (lastPendingDelegate.epoch >= nextEpoch) {
                lastPendingDelegate.amount += uint64(amount / 1 gwei);
            } else {
                delegation.delegateQueue.push(DelegationOpDelegate({epoch : nextEpoch, amount : uint64(amount / 1 gwei)}));
            }
        } else {
            delegation.delegateQueue.push(DelegationOpDelegate({epoch : nextEpoch, amount : uint64(amount / 1 gwei)}));
        }
        // emit event
        emit Delegated(toValidator, fromAddress, amount);
    }

    function _undelegateFrom(address toAddress, address fromValidator, uint256 amount) internal {
    }

    function _transferDelegation(address validator, address fromAddress, address toAddress, uint256 amount) internal {
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
        uint64 activeValidatorsLimit = _activeValidatorsSize;
        address[] memory activeValidators;
        if (_validatorsList.length >= activeValidatorsLimit) {
            activeValidators = new address[](activeValidatorsLimit);
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

    //    function _slashValidatorsAndConfirmRewards() internal {
    //        // do it only once some interval
    //        if (block.number < _recentSlashAndRewardDistribution + SLASH_AND_COMMIT_VALIDATOR_BLOCK_INTERVAL) {
    //            return;
    //        }
    //        uint256 totalSlashedIncome = 0;
    //        uint256 goodValidators = 0;
    //        // calculate average slashing payout from all slashed validators, we think that
    //        // validator is slashed if validator has at least one block miss.
    //        for (uint256 i = 0; i < _validatorsList.length; i++) {
    //            Validator memory validator = _validatorsMap[_validatorsList[i]];
    //            if (validator.totalSlashes > 0) {
    //                totalSlashedIncome += validator.pendingBalance;
    //            } else {
    //                goodValidators++;
    //            }
    //        }
    //        // distribute total slashed balance between honest validators and pay all dust to the system
    //        if (goodValidators > 0) {
    //            uint256 averageSlashingPayout = totalSlashedIncome / goodValidators;
    //            for (uint256 i = 0; i < _validatorsList.length; i++) {
    //                Validator memory validator = _validatorsMap[_validatorsList[i]];
    //                if (validator.totalSlashes > 0) {
    //                    continue;
    //                }
    //                validator.pendingBalance += averageSlashingPayout;
    //            }
    //            uint256 distributionDust = totalSlashedIncome - averageSlashingPayout * goodValidators;
    //            _systemFee += distributionDust;
    //        } else {
    //            _systemFee += totalSlashedIncome;
    //        }
    //        // confirm pending validator rewards and reset slashing state
    //        for (uint256 i = 0; i < _validatorsList.length; i++) {
    //            Validator memory validator = _validatorsMap[_validatorsList[i]];
    //            if (validator.totalSlashes > 0) {
    //                // for slashed validator lets just reset all his stats and
    //                // let him start again, probably its better to put this validator in jail
    //                // for some period of time
    //                validator.totalSlashes = 0;
    //                validator.pendingBalance = 0;
    //            } else {
    //                // move pending validator's balance to confirmed, it means that now validator
    //                // can distribute this rewards between delegates
    //                validator.confirmedBalance += validator.pendingBalance;
    //                validator.pendingBalance = 0;
    //            }
    //        }
    //        // update latest reward commit block
    //        _recentSlashAndRewardDistribution = uint64(block.number);
    //    }
    //
    //    function _releasePendingUndelegate(ValidatorDelegation memory delegation) internal {
    //        uint256 transferAmount = delegation.pendingUndelegate;
    //        // if staker doesn't have pending undelegates or staker is still in lock period then just exit
    //        if (transferAmount == 0 || delegation.undelegateBlockedBefore == 0 || block.number < delegation.undelegateBlockedBefore) {
    //            return;
    //        }
    //        // reset lock period for future undelegates
    //        delegation.pendingUndelegate = 0;
    //        delegation.undelegateBlockedBefore = 0;
    //        // transfer tokens to the user
    //        address payable payableAccount = payable(delegation.accountAddress);
    //        (bool sent) = payableAccount.call{gas : 30_000, value : msg.value}("");
    //        require(sent, "Staking: transfer failed");
    //    }

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
