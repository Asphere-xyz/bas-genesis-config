// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "./Injector.sol";

contract Staking is IStaking, InjectorContextHolder {

    /**
     * Here is min/max commission rates, lets don't allow to set more than 30% of validator commission
     * Commission rate is a percents divided by 100 stored with 0 decimals as percents*100 (=pc/1e2*1e4)
     * Here is some examples:
     * + 0.3% => 0.3*100=30
     * + 3% => 3*100=300
     * + 30% => 30*100=3000
     */
    uint16 internal constant COMMISSION_RATE_MIN_VALUE = 0; // 0%
    uint16 internal constant COMMISSION_RATE_MAX_VALUE = 3000; // 30%

    // validator events
    event Added(address validator, address owner, uint8 status, uint16 commissionRate);
    event Modified(address validator, address owner, uint8 status, uint16 commissionRate);
    event Removed(address validator);
    event OwnerClaimed(address validator, uint256 amount, uint64 epoch);
    event Slashed(address validator, uint32 slashes, uint64 epoch);
    event Jailed(address validator, uint64 epoch);
    // staker events
    event Delegated(address validator, address staker, uint256 amount, uint64 epoch);
    event Undelegated(address validator, address staker, uint256 amount, uint64 epoch);
    event Claimed(address validator, address staker, uint256 amount, uint64 epoch);

    event ConsensusParamsUpdated(
        uint32 activeValidatorsLength,
        uint32 epochBlockInterval,
        uint32 misdemeanorThreshold,
        uint32 felonyThreshold,
        uint32 validatorJailEpochLength,
        uint32 undelegatePeriod
    );

    enum ValidatorStatus {
        NotFound,
        Active,
        Pending,
        Jail
    }

    struct ValidatorSnapshot {
        uint96 totalRewards;
        uint64 totalDelegated;
        uint32 slashesCount;
        uint16 commissionRate;
    }

    struct Validator {
        address validatorAddress;
        address ownerAddress;
        ValidatorStatus status;
        uint64 changedAt;
        uint64 jailedBefore;
        uint64 claimedAt;
    }

    struct DelegationOpDelegate {
        uint64 amount;
        uint64 epoch;
    }

    struct DelegationOpUndelegate {
        uint256 amount;
        uint64 epoch;
    }

    struct ValidatorDelegation {
        DelegationOpDelegate[] delegateQueue;
        uint64 delegateGap;
        DelegationOpUndelegate[] undelegateQueue;
        uint64 undelegateGap;
    }

    // mapping from validator address to validator
    mapping(address => Validator) internal _validatorsMap;
    // mapping from validator owner to validator address
    mapping(address => address) internal _validatorOwners;
    // list of all validators that are in validators mapping
    address[] internal _validatorsList;
    // mapping with stakers to validators at epoch (validator -> delegator -> delegation)
    mapping(address => mapping(address => ValidatorDelegation)) internal _validatorDelegations;
    // mapping with validator snapshots per each epoch (validator -> epoch -> snapshot)
    mapping(address => mapping(uint64 => ValidatorSnapshot)) internal _validatorSnapshots;
    // consensus parameters
    ConsensusParams internal _consensusParams;

    constructor(
        address[] memory validators,
        uint32 activeValidatorsLength,
        uint32 epochBlockInterval,
        uint32 misdemeanorThreshold,
        uint32 felonyThreshold,
        uint32 validatorJailEpochLength,
        uint32 undelegatePeriod
    ) {
        // system params
        _consensusParams.activeValidatorsLength = activeValidatorsLength;
        _consensusParams.epochBlockInterval = epochBlockInterval;
        _consensusParams.misdemeanorThreshold = misdemeanorThreshold;
        _consensusParams.felonyThreshold = felonyThreshold;
        _consensusParams.validatorJailEpochLength = validatorJailEpochLength;
        _consensusParams.undelegatePeriod = undelegatePeriod;
        // init validators
        for (uint256 i = 0; i < validators.length; i++) {
            _addValidator(validators[i], validators[i], ValidatorStatus.Active, 0, 0);
        }
    }

    function getConsensusParams() external view override returns (ConsensusParams memory) {
        return _consensusParams;
    }

    function updateConsensusParams(ConsensusParams calldata consensusParams) external onlyFromGovernance override {
        // update consensus params
        _consensusParams = consensusParams;
        // emit event indicating consensus param change
        emit ConsensusParamsUpdated(
            consensusParams.activeValidatorsLength,
            consensusParams.epochBlockInterval,
            consensusParams.misdemeanorThreshold,
            consensusParams.felonyThreshold,
            consensusParams.validatorJailEpochLength,
            consensusParams.undelegatePeriod
        );
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
        return (delegatedAmount = uint256(snapshot.amount) * 1 gwei, atEpoch = snapshot.epoch);
    }

    function getValidatorStatus(address validatorAddress) external view override returns (
        address ownerAddress,
        uint8 status,
        uint256 totalDelegated,
        uint32 slashesCount,
        uint64 changedAt,
        uint64 jailedBefore,
        uint64 claimedAt
    ) {
        Validator memory validator = _validatorsMap[validatorAddress];
        ValidatorSnapshot memory snapshot = _validatorSnapshots[validator.validatorAddress][validator.changedAt];
        return (
        ownerAddress = validator.ownerAddress,
        status = uint8(validator.status),
        totalDelegated = uint256(snapshot.totalDelegated) * 1 gwei,
        slashesCount = snapshot.slashesCount,
        changedAt = validator.changedAt,
        jailedBefore = validator.jailedBefore,
        claimedAt = validator.claimedAt
        );
    }

    function getValidatorStatusAtEpoch(address validatorAddress, uint64 epoch) external view returns (
        address ownerAddress,
        uint8 status,
        uint256 totalDelegated,
        uint32 slashesCount,
        uint64 changedAt,
        uint64 jailedBefore,
        uint64 claimedAt
    ) {
        Validator memory validator = _validatorsMap[validatorAddress];
        ValidatorSnapshot memory snapshot = _touchValidatorSnapshotImmutable(validator, epoch);
        return (
        ownerAddress = validator.ownerAddress,
        status = uint8(validator.status),
        totalDelegated = uint256(snapshot.totalDelegated) * 1 gwei,
        slashesCount = snapshot.slashesCount,
        changedAt = validator.changedAt,
        jailedBefore = validator.jailedBefore,
        claimedAt = validator.claimedAt
        );
    }

    function getValidatorByOwner(address owner) external view override returns (address) {
        return _validatorOwners[owner];
    }

    function releaseValidatorFromJail(address validatorAddress) external {
        // make sure validator is in jail
        Validator memory validator = _validatorsMap[validatorAddress];
        require(validator.status == ValidatorStatus.Jail, "Staking: validator not in jail");
        // only validator owner
        require(msg.sender == validator.ownerAddress, "Staking: only validator owner");
        require(_currentEpoch() >= validator.jailedBefore, "Staking: still in jail");
        // update validator status
        validator.status = ValidatorStatus.Active;
        _validatorsMap[validatorAddress] = validator;
    }

    function _totalDelegatedToValidator(Validator memory validator) internal view returns (uint256) {
        ValidatorSnapshot memory snapshot = _validatorSnapshots[validator.validatorAddress][validator.changedAt];
        return uint256(snapshot.totalDelegated) * 1 gwei;
    }

    function delegate(address validatorAddress) payable external override {
        _delegateTo(msg.sender, validatorAddress, msg.value);
    }

    function undelegate(address validatorAddress, uint256 amount) payable external override {
        _undelegateFrom(msg.sender, validatorAddress, amount);
    }

    function currentEpoch() external view returns (uint64) {
        return _currentEpoch();
    }

    function _currentEpoch() internal view returns (uint64) {
        return uint64(block.number / _consensusParams.epochBlockInterval + 0);
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
        if (epoch > validator.changedAt) {
            validator.changedAt = epoch;
        }
        return snapshot;
    }

    function _touchValidatorSnapshotImmutable(Validator memory validator, uint64 epoch) internal view returns (ValidatorSnapshot memory) {
        ValidatorSnapshot memory snapshot = _validatorSnapshots[validator.validatorAddress][epoch];
        // if snapshot is already initialized then just return it
        if (snapshot.totalDelegated > 0) {
            return snapshot;
        }
        // find previous snapshot to copy parameters from it
        ValidatorSnapshot memory lastModifiedSnapshot = _validatorSnapshots[validator.validatorAddress][validator.changedAt];
        // last modified snapshot might store zero value, for first delegation it might happen and its not critical
        snapshot.totalDelegated = lastModifiedSnapshot.totalDelegated;
        snapshot.commissionRate = lastModifiedSnapshot.commissionRate;
        // return existing or new snapshot
        return snapshot;
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
        ValidatorSnapshot storage validatorSnapshot = _touchValidatorSnapshot(validator, nextEpoch);
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
        delegation.undelegateQueue.push(DelegationOpUndelegate({amount : amount, epoch : nextEpoch + _consensusParams.undelegatePeriod}));
        // emit event with the next epoch number
        emit Undelegated(fromValidator, toDelegator, amount, nextEpoch);
    }

    function _claimDelegatorRewardsAndPendingUndelegates(address validator, address delegator) internal {
        ValidatorDelegation storage delegation = _validatorDelegations[validator][delegator];
        // lets fail fast if there is nothing to claim
        if (delegation.delegateGap >= delegation.delegateQueue.length &&
            delegation.undelegateGap >= delegation.undelegateQueue.length
        ) {
            revert("Staking: nothing to claim");
        }
        uint256 availableFunds = 0;
        uint64 beforeEpoch = _currentEpoch();
        // process delegate queue to calculate staking rewards
        while (delegation.delegateGap < delegation.delegateQueue.length) {
            DelegationOpDelegate memory delegateOp = delegation.delegateQueue[delegation.delegateGap];
            if (delegateOp.epoch >= beforeEpoch) {
                break;
            }
            uint256 voteChangedAtEpoch = 0;
            if (delegation.delegateGap < delegation.delegateQueue.length - 1) {
                voteChangedAtEpoch = delegation.delegateQueue[delegation.delegateGap + 1].epoch;
            }
            for (; delegateOp.epoch < beforeEpoch && (voteChangedAtEpoch == 0 || delegateOp.epoch < voteChangedAtEpoch); delegateOp.epoch++) {
                ValidatorSnapshot memory validatorSnapshot = _validatorSnapshots[validator][delegateOp.epoch];
                if (validatorSnapshot.totalDelegated == 0) {
                    continue;
                }
                (uint256 delegatorFee, /*uint256 ownerFee*/, /*uint256 systemFee*/) = _calcValidatorSnapshotEpochPayout(validatorSnapshot);
                availableFunds += delegatorFee * delegateOp.amount / validatorSnapshot.totalDelegated;
            }
            delete delegation.delegateQueue[delegation.delegateGap];
            ++delegation.delegateGap;
        }
        // process all items from undelegate queue
        while (delegation.undelegateGap < delegation.undelegateQueue.length) {
            DelegationOpUndelegate memory undelegateOp = delegation.undelegateQueue[delegation.undelegateGap];
            if (undelegateOp.epoch > beforeEpoch) {
                break;
            }
            availableFunds += undelegateOp.amount;
            delete delegation.undelegateQueue[delegation.undelegateGap];
            ++delegation.undelegateGap;
        }
        // send available for claim funds to delegator
        address payable payableDelegator = payable(delegator);
        payableDelegator.transfer(availableFunds);
        // emit event
        emit Claimed(validator, delegator, availableFunds, beforeEpoch);
    }

    function _calcDelegatorRewardsAndPendingUndelegates(address validator, address delegator, uint64 beforeEpoch) internal view returns (uint256) {
        ValidatorDelegation memory delegation = _validatorDelegations[validator][delegator];
        uint256 availableFunds = 0;
        // process delegate queue to calculate staking rewards
        while (delegation.delegateGap < delegation.delegateQueue.length) {
            DelegationOpDelegate memory delegateOp = delegation.delegateQueue[delegation.delegateGap];
            if (delegateOp.epoch >= beforeEpoch) {
                break;
            }
            uint256 voteChangedAtEpoch = 0;
            if (delegation.delegateGap < delegation.delegateQueue.length - 1) {
                voteChangedAtEpoch = delegation.delegateQueue[delegation.delegateGap + 1].epoch;
            }
            for (; delegateOp.epoch < beforeEpoch && (voteChangedAtEpoch == 0 || delegateOp.epoch < voteChangedAtEpoch); delegateOp.epoch++) {
                ValidatorSnapshot memory validatorSnapshot = _validatorSnapshots[validator][delegateOp.epoch];
                if (validatorSnapshot.totalDelegated == 0) {
                    continue;
                }
                (uint256 delegatorFee, /*uint256 ownerFee*/, /*uint256 systemFee*/) = _calcValidatorSnapshotEpochPayout(validatorSnapshot);
                availableFunds += delegatorFee * delegateOp.amount / validatorSnapshot.totalDelegated;
            }
            ++delegation.delegateGap;
        }
        // process all items from undelegate queue
        while (delegation.undelegateGap < delegation.undelegateQueue.length) {
            DelegationOpUndelegate memory undelegateOp = delegation.undelegateQueue[delegation.undelegateGap];
            if (undelegateOp.epoch > beforeEpoch) {
                break;
            }
            availableFunds += undelegateOp.amount;
            ++delegation.undelegateGap;
        }
        // return available for claim funds
        return availableFunds;
    }

    function _claimValidatorOwnerRewards(Validator storage validator, uint64 beforeEpoch) internal {
        uint256 availableFunds = 0;
        uint256 systemFee = 0;
        for (; validator.claimedAt < beforeEpoch; validator.claimedAt++) {
            ValidatorSnapshot memory validatorSnapshot = _validatorSnapshots[validator.validatorAddress][validator.claimedAt];
            (/*uint256 delegatorFee*/, uint256 ownerFee, uint256 slashingFee) = _calcValidatorSnapshotEpochPayout(validatorSnapshot);
            availableFunds += ownerFee;
            systemFee += slashingFee;
        }
        address payable payableOwner = payable(validator.ownerAddress);
        payableOwner.transfer(availableFunds);
        // if we have system fee then pay it to treasury account
        if (systemFee > 0) {
            _payToTreasury(systemFee);
        }
        emit OwnerClaimed(validator.validatorAddress, availableFunds, beforeEpoch);
    }

    function _calcValidatorOwnerRewards(Validator memory validator, uint64 beforeEpoch) internal view returns (uint256) {
        uint256 availableFunds = 0;
        for (; validator.claimedAt < beforeEpoch; validator.claimedAt++) {
            ValidatorSnapshot memory validatorSnapshot = _validatorSnapshots[validator.validatorAddress][validator.claimedAt];
            (/*uint256 delegatorFee*/, uint256 ownerFee, /*uint256 systemFee*/) = _calcValidatorSnapshotEpochPayout(validatorSnapshot);
            availableFunds += ownerFee;
        }
        return availableFunds;
    }

    function _calcValidatorSnapshotEpochPayout(ValidatorSnapshot memory validatorSnapshot) internal view returns (uint256 delegatorFee, uint256 ownerFee, uint256 systemFee) {
        // detect validator slashing to transfer all rewards to treasury
        if (validatorSnapshot.slashesCount >= _consensusParams.misdemeanorThreshold) {
            return (delegatorFee = 0, ownerFee = 0, systemFee = validatorSnapshot.totalRewards);
        } else if (validatorSnapshot.totalDelegated == 0) {
            return (delegatorFee = 0, ownerFee = validatorSnapshot.totalRewards, systemFee = 0);
        }
        // ownerFee_(18+4-4=18) = totalRewards_18 * commissionRate_4 / 1e4
        ownerFee = validatorSnapshot.totalRewards * validatorSnapshot.commissionRate / 1e4;
        // delegatorRewards = totalRewards - ownerFee
        delegatorFee = validatorSnapshot.totalRewards - ownerFee;
        // default system fee is zero for epoch
        systemFee = 0;
    }

    function registerValidator(address validatorAddress, uint16 commissionRate) payable external override {
        address validatorOwner = msg.sender;
        uint256 initialStake = msg.value;
        // initial stake requirements
        require(initialStake >= 1 ether, "Staking: amount too low");
        require(initialStake % 1 ether == 0, "Staking: amount shouldn't have a remainder");
        // add new pending validator
        _addValidator(validatorAddress, validatorOwner, ValidatorStatus.Pending, commissionRate, uint64(initialStake / 1 gwei));
    }

    function addValidator(address account) external onlyFromGovernance virtual override {
        _addValidator(account, account, ValidatorStatus.Active, 0, 0);
    }

    function _addValidator(address validatorAddress, address validatorOwner, ValidatorStatus status, uint16 commissionRate, uint64 initialStake) internal {
        uint64 nextEpoch = _nextEpoch();
        // validator commission rate
        require(commissionRate >= COMMISSION_RATE_MIN_VALUE && commissionRate <= COMMISSION_RATE_MAX_VALUE, "Staking: bad commission rate");
        // init validator default params
        Validator memory validator = _validatorsMap[validatorAddress];
        require(_validatorsMap[validatorAddress].status == ValidatorStatus.NotFound, "Staking: validator already exist");
        validator.validatorAddress = validatorAddress;
        validator.ownerAddress = validatorOwner;
        validator.status = status;
        validator.changedAt = nextEpoch;
        _validatorsMap[validatorAddress] = validator;
        // save validator owner
        require(_validatorOwners[validatorOwner] == address(0x00), "Staking: owner already in use");
        _validatorOwners[validatorOwner] = validatorAddress;
        // add new validator to array
        _validatorsList.push(validatorAddress);
        // push initial validator snapshot at zero epoch with default params
        _validatorSnapshots[validatorAddress][nextEpoch] = ValidatorSnapshot(0, initialStake, 0, commissionRate);
        // delegate initial stake to validator owner
        ValidatorDelegation storage delegation = _validatorDelegations[validatorAddress][validatorOwner];
        require(delegation.delegateQueue.length == 0, "Staking: delegation queue is not empty");
        delegation.delegateQueue.push(DelegationOpDelegate(initialStake, nextEpoch));
        // emit event
        emit Added(validatorAddress, validatorOwner, uint8(status), commissionRate);
    }

    function removeValidator(address account) external onlyFromGovernance virtual override {
        _removeValidator(account);
    }

    function _removeValidator(address account) internal {
        Validator memory validator = _validatorsMap[account];
        require(validator.status != ValidatorStatus.NotFound, "Staking: validator not found");
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
        delete _validatorOwners[validator.ownerAddress];
        delete _validatorsMap[account];
        // emit event about it
        emit Removed(account);
    }

    function activateValidator(address validator) external onlyFromGovernance virtual override {
        _activateValidator(validator);
    }

    function _activateValidator(address validatorAddress) internal {
        Validator memory validator = _validatorsMap[validatorAddress];
        require(_validatorsMap[validatorAddress].status == ValidatorStatus.Pending, "Staking: not pending validator");
        validator.status = ValidatorStatus.Active;
        _validatorsMap[validatorAddress] = validator;
    }


    function disableValidator(address validator) external onlyFromGovernance virtual override {
        _disableValidator(validator);
    }

    function _disableValidator(address validatorAddress) internal {
        Validator memory validator = _validatorsMap[validatorAddress];
        require(_validatorsMap[validatorAddress].status == ValidatorStatus.Active, "Staking: not active validator");
        validator.status = ValidatorStatus.Pending;
        _validatorsMap[validatorAddress] = validator;
    }

    function changeValidatorCommissionRate(address validatorAddress, uint16 commissionRate) external {
        require(commissionRate >= COMMISSION_RATE_MIN_VALUE && commissionRate <= COMMISSION_RATE_MAX_VALUE, "Staking: bad commission rate");
        Validator memory validator = _validatorsMap[validatorAddress];
        require(validator.status != ValidatorStatus.NotFound, "Staking: validator not found");
        require(validator.ownerAddress == msg.sender, "Staking: only validator owner");
        ValidatorSnapshot storage snapshot = _touchValidatorSnapshot(validator, _nextEpoch());
        snapshot.commissionRate = commissionRate;
        _validatorsMap[validatorAddress] = validator;
        emit Modified(validator.validatorAddress, validator.ownerAddress, uint8(validator.status), commissionRate);
    }

    function changeValidatorOwner(address validatorAddress, address newOwner) external override {
        Validator memory validator = _validatorsMap[validatorAddress];
        require(validator.ownerAddress == msg.sender, "Staking: only validator owner");
        delete _validatorOwners[validator.ownerAddress];
        validator.ownerAddress = newOwner;
        _validatorOwners[newOwner] = validatorAddress;
        _validatorsMap[validatorAddress] = validator;
        ValidatorSnapshot storage snapshot = _touchValidatorSnapshot(validator, _nextEpoch());
        emit Modified(validator.validatorAddress, validator.ownerAddress, uint8(validator.status), snapshot.commissionRate);
    }

    function isValidatorActive(address account) external override view returns (bool) {
        if (_validatorsMap[account].status != ValidatorStatus.Active) {
            return false;
        }
        address[] memory topValidators = _getValidators();
        for (uint256 i = 0; i < topValidators.length; i++) {
            if (topValidators[i] == account) return true;
        }
        return false;
    }

    function isValidator(address account) external override view returns (bool) {
        return _validatorsMap[account].status != ValidatorStatus.NotFound;
    }

    function _getValidators() internal view returns (address[] memory) {
        uint256 n = _validatorsList.length;
        address[] memory orderedValidators = new address[](n);
        for (uint256 i = 0; i < n; i++) {
            orderedValidators[i] = _validatorsList[i];
        }
        // we need to select k top validators out of n
        uint256 k = _consensusParams.activeValidatorsLength;
        if (k > n) {
            k = n;
        }
        for (uint256 i = 0; i < k; i++) {
            uint256 nextValidator = i;
            Validator memory currentMax = _validatorsMap[orderedValidators[nextValidator]];
            for (uint256 j = i + 1; j < n; j++) {
                Validator memory current = _validatorsMap[orderedValidators[j]];
                if (_totalDelegatedToValidator(currentMax) < _totalDelegatedToValidator(current)) {
                    nextValidator = j;
                    currentMax = current;
                }
            }
            address backup = orderedValidators[i];
            orderedValidators[i] = orderedValidators[nextValidator];
            orderedValidators[nextValidator] = backup;
        }
        // this is to cut array to first k elements without copying
        assembly {
            mstore(orderedValidators, k)
        }
        return orderedValidators;
    }

    function getValidators() external view override returns (address[] memory) {
        return _getValidators();
    }

    function deposit(address validatorAddress) external payable onlyFromCoinbase onlyZeroGasPrice virtual override {
        _depositFee(validatorAddress);
    }

    function _depositFee(address validatorAddress) internal {
        require(msg.value > 0, "Staking: deposit is zero");
        // make sure validator is active
        Validator memory validator = _validatorsMap[validatorAddress];
        require(validator.status == ValidatorStatus.Active, "Staking: validator not active");
        // increase total pending rewards for validator for current epoch
        ValidatorSnapshot storage currentSnapshot = _touchValidatorSnapshot(validator, _currentEpoch());
        currentSnapshot.totalRewards += uint96(msg.value);
    }

    function getValidatorFee(address validatorAddress) external override view returns (uint256) {
        // make sure validator exists at least
        Validator memory validator = _validatorsMap[validatorAddress];
        require(validator.status != ValidatorStatus.NotFound, "Staking: validator not found");
        // calc validator rewards
        return _calcValidatorOwnerRewards(validator, _currentEpoch());
    }

    function getPendingValidatorFee(address validatorAddress) external override view returns (uint256) {
        // make sure validator exists at least
        Validator memory validator = _validatorsMap[validatorAddress];
        require(validator.status != ValidatorStatus.NotFound, "Staking: validator not found");
        // calc validator rewards
        return _calcValidatorOwnerRewards(validator, _nextEpoch());
    }

    function claimValidatorFee(address validatorAddress) external override {
        // make sure validator exists at least
        Validator storage validator = _validatorsMap[validatorAddress];
        require(validator.status != ValidatorStatus.NotFound, "Staking: validator not found");
        // only validator owner can claim deposit fee
        require(msg.sender == validator.ownerAddress, "Staking: only validator owner");
        // claim all validator fees
        _claimValidatorOwnerRewards(validator, _currentEpoch());
    }

    function getDelegatorFee(address validatorAddress, address delegatorAddress) external override view returns (uint256) {
        return _calcDelegatorRewardsAndPendingUndelegates(validatorAddress, delegatorAddress, _currentEpoch());
    }

    function getPendingDelegatorFee(address validatorAddress, address delegatorAddress) external override view returns (uint256) {
        return _calcDelegatorRewardsAndPendingUndelegates(validatorAddress, delegatorAddress, _nextEpoch());
    }

    function claimDelegatorFee(address validatorAddress) external override {
        // make sure validator exists at least
        Validator storage validator = _validatorsMap[validatorAddress];
        require(validator.status != ValidatorStatus.NotFound, "Staking: validator not found");
        // claim all confirmed delegator fees including undelegates
        _claimDelegatorRewardsAndPendingUndelegates(validatorAddress, msg.sender);
    }

    function _payToTreasury(uint256 amount) internal {
        payable(address(_systemRewardContract)).call{value : amount}("");
    }

    function slash(address validatorAddress) external onlyFromCoinbaseOrSlashingIndicator onlyZeroGasPrice onlyOncePerBlock virtual override {
        _slashValidator(validatorAddress);
    }

    function _slashValidator(address validatorAddress) internal {
        // make sure validator was active
        Validator memory validator = _validatorsMap[validatorAddress];
        require(validator.status == ValidatorStatus.Active, "Staking: validator not found");
        uint64 epoch = _currentEpoch();
        // increase slashes for current epoch
        ValidatorSnapshot storage currentSnapshot = _touchValidatorSnapshot(validator, epoch);
        uint32 slashesCount = currentSnapshot.slashesCount + 1;
        currentSnapshot.slashesCount = slashesCount;
        // validator state might change, lets update it
        _validatorsMap[validatorAddress] = validator;
        // if validator has a lot of misses then put it in jail for 1 week (if epoch is 1 day)
        if (slashesCount == _consensusParams.felonyThreshold) {
            validator.jailedBefore = _currentEpoch() + _consensusParams.validatorJailEpochLength;
            validator.status = ValidatorStatus.Jail;
            _validatorsMap[validatorAddress] = validator;
            emit Jailed(validatorAddress, epoch);
        }
        // emit event
        emit Slashed(validatorAddress, slashesCount, epoch);
    }
}
