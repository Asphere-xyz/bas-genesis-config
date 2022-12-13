// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "./StakingStorageLayout.sol";

contract StakingValidatorRegistry is StakingStorageLayout, RetryMixin, IStakingValidatorRegistry {

    constructor(ConstructorArguments memory constructorArgs) InjectorContextHolder(constructorArgs) {
    }

    function getValidatorStatus(address validatorAddress) external view returns (
        address ownerAddress,
        uint8 status,
        uint256 totalDelegated,
        uint32 slashesCount,
        uint64 changedAt,
        uint64 jailedBefore,
        uint64 claimedAt,
        uint16 commissionRate,
        uint96 totalRewards
    ) {
        Validator memory validator = _validatorsMap[validatorAddress];
        ValidatorSnapshot memory snapshot = _validatorSnapshots[validator.validatorAddress][validator.changedAt];
        return (
        ownerAddress = validator.ownerAddress,
        status = uint8(validator.status),
        totalDelegated = uint256(snapshot.totalDelegated) * BALANCE_COMPACT_PRECISION,
        slashesCount = snapshot.slashesCount,
        changedAt = validator.changedAt,
        jailedBefore = validator.jailedBefore,
        claimedAt = validator.claimedAt,
        commissionRate = snapshot.commissionRate,
        totalRewards = snapshot.totalRewards
        );
    }

    function getValidatorStatusAtEpoch(address validatorAddress, uint64 epoch) external view returns (
        address ownerAddress,
        uint8 status,
        uint256 totalDelegated,
        uint32 slashesCount,
        uint64 changedAt,
        uint64 jailedBefore,
        uint64 claimedAt,
        uint16 commissionRate,
        uint96 totalRewards
    ) {
        Validator memory validator = _validatorsMap[validatorAddress];
        ValidatorSnapshot memory snapshot = _touchValidatorSnapshotImmutable(validator, epoch);
        return (
        ownerAddress = validator.ownerAddress,
        status = uint8(validator.status),
        totalDelegated = uint256(snapshot.totalDelegated) * BALANCE_COMPACT_PRECISION,
        slashesCount = snapshot.slashesCount,
        changedAt = validator.changedAt,
        jailedBefore = validator.jailedBefore,
        claimedAt = validator.claimedAt,
        commissionRate = snapshot.commissionRate,
        totalRewards = snapshot.totalRewards
        );
    }

    function getValidatorByOwner(address owner) external view returns (address) {
        return _validatorOwners[owner];
    }

    function releaseValidatorFromJail(address validatorAddress) external {
        // make sure validator is in jail
        Validator memory validator = _validatorsMap[validatorAddress];
        require(validator.status == ValidatorStatus.Jail, "bad status");
        // only validator owner
        require(msg.sender == validator.ownerAddress, "only owner");
        require(_currentEpoch() >= validator.jailedBefore, "still in jail");
        // release validator from jail
        _releaseValidatorFromJail(validator);
    }

    function forceUnJailValidator(address validatorAddress) external override onlyFromGovernance {
        // make sure validator is in jail
        Validator memory validator = _validatorsMap[validatorAddress];
        require(validator.status == ValidatorStatus.Jail, "bad status");
        // release validator from jail
        _releaseValidatorFromJail(validator);
    }

    function _releaseValidatorFromJail(Validator memory validator) internal {
        address validatorAddress = validator.validatorAddress;
        // update validator status
        validator.status = ValidatorStatus.Active;
        validator.jailedBefore = 0;
        _validatorsMap[validatorAddress] = validator;
        _activeValidatorsList.push(validatorAddress);
        // emit event
        emit ValidatorReleased(validatorAddress, _currentEpoch());
    }

    function registerValidator(address validatorAddress, bytes calldata votingKey, uint16 commissionRate) payable external {
        uint256 initialStake = msg.value;
        // // initial stake amount should be greater than minimum validator staking amount
        require(initialStake >= _STAKING_CONFIG_CONTRACT.getMinValidatorStakeAmount(), "too low");
        require(initialStake % BALANCE_COMPACT_PRECISION == 0, "no remainder");
        // add new validator as pending
        _addValidator(validatorAddress, votingKey, msg.sender, ValidatorStatus.Pending, commissionRate, initialStake, _nextEpoch());
    }

    function addValidator(address account, bytes calldata votingKey) external onlyFromGovernance virtual {
        _addValidator(account, votingKey, account, ValidatorStatus.Active, 0, 0, _nextEpoch());
    }

    function removeValidator(address account) external onlyFromGovernance virtual {
        Validator memory validator = _validatorsMap[account];
        require(validator.status != ValidatorStatus.NotFound, "not found");
        // don't allow to remove validator w/ active delegations
        ValidatorSnapshot memory snapshot = _validatorSnapshots[validator.validatorAddress][validator.changedAt];
        require(snapshot.totalDelegated == 0, "has delegations");
        // remove validator from active list if exists
        _removeValidatorFromActiveList(account);
        // remove from validators map
        delete _validatorOwners[validator.ownerAddress];
        delete _validatorsMap[account];
        // emit event about it
        emit ValidatorRemoved(account);
    }

    function _removeValidatorFromActiveList(address validatorAddress) internal {
        // find index of validator in validator set
        int256 indexOf = - 1;
        for (uint256 i = 0; i < _activeValidatorsList.length; i++) {
            if (_activeValidatorsList[i] != validatorAddress) continue;
            indexOf = int256(i);
            break;
        }
        // remove validator from array (since we remove only active it might not exist in the list)
        if (indexOf >= 0) {
            if (_activeValidatorsList.length > 1 && uint256(indexOf) != _activeValidatorsList.length - 1) {
                _activeValidatorsList[uint256(indexOf)] = _activeValidatorsList[_activeValidatorsList.length - 1];
            }
            _activeValidatorsList.pop();
        }
    }

    function activateValidator(address validatorAddress) external onlyFromGovernance virtual {
        Validator memory validator = _validatorsMap[validatorAddress];
        require(_validatorsMap[validatorAddress].status == ValidatorStatus.Pending, "bad status");
        _activeValidatorsList.push(validatorAddress);
        validator.status = ValidatorStatus.Active;
        _validatorsMap[validatorAddress] = validator;
        ValidatorSnapshot storage snapshot = _touchValidatorSnapshot(validator, _nextEpoch());
        emit ValidatorModified(validatorAddress, validator.ownerAddress, uint8(validator.status), snapshot.commissionRate);
    }

    function disableValidator(address validatorAddress) external onlyFromGovernance virtual {
        Validator memory validator = _validatorsMap[validatorAddress];
        require(validator.status == ValidatorStatus.Active || validator.status == ValidatorStatus.Jail, "bad status");
        _removeValidatorFromActiveList(validatorAddress);
        validator.status = ValidatorStatus.Pending;
        _validatorsMap[validatorAddress] = validator;
        ValidatorSnapshot storage snapshot = _touchValidatorSnapshot(validator, _nextEpoch());
        emit ValidatorModified(validatorAddress, validator.ownerAddress, uint8(validator.status), snapshot.commissionRate);
    }

    function changeValidatorCommissionRate(address validatorAddress, uint16 commissionRate) external {
        require(commissionRate >= COMMISSION_RATE_MIN_VALUE && commissionRate <= COMMISSION_RATE_MAX_VALUE, "bad commission");
        Validator memory validator = _validatorsMap[validatorAddress];
        require(validator.status != ValidatorStatus.NotFound, "not found");
        require(validator.ownerAddress == msg.sender, "only owner");
        ValidatorSnapshot storage snapshot = _touchValidatorSnapshot(validator, _nextEpoch());
        snapshot.commissionRate = commissionRate;
        _validatorsMap[validatorAddress] = validator;
        emit ValidatorModified(validator.validatorAddress, validator.ownerAddress, uint8(validator.status), commissionRate);
    }

    function changeValidatorOwner(address validatorAddress, address newOwner) external {
        Validator memory validator = _validatorsMap[validatorAddress];
        require(validator.ownerAddress == msg.sender, "only owner");
        require(_validatorOwners[newOwner] == address(0x00), "owner in use");
        delete _validatorOwners[validator.ownerAddress];
        validator.ownerAddress = newOwner;
        _validatorOwners[newOwner] = validatorAddress;
        _validatorsMap[validatorAddress] = validator;
        ValidatorSnapshot storage snapshot = _touchValidatorSnapshot(validator, _nextEpoch());
        emit ValidatorModified(validator.validatorAddress, validator.ownerAddress, uint8(validator.status), snapshot.commissionRate);
    }

    function changeVotingKey(address validatorAddress, bytes calldata newVotingKey) external override {
        Validator memory validator = _validatorsMap[validatorAddress];
        require(validator.ownerAddress == msg.sender, "only owner");
        validator.votingKey = newVotingKey;
        _validatorsMap[validatorAddress] = validator;
        ValidatorSnapshot storage snapshot = _touchValidatorSnapshot(validator, _nextEpoch());
        emit ValidatorModified(validator.validatorAddress, validator.ownerAddress, uint8(validator.status), snapshot.commissionRate);
    }

    function slash(address validator) external onlyFromSlashingIndicator {
        _slashValidator(validator);
    }

    function isValidatorActive(address account) external view returns (bool) {
        if (_validatorsMap[account].status != ValidatorStatus.Active) {
            return false;
        }
        (address[] memory topValidators,) = _getValidatorsWithVotingKeys();
        for (uint256 i = 0; i < topValidators.length; i++) {
            if (topValidators[i] == account) return true;
        }
        return false;
    }

    function isValidator(address account) external view returns (bool) {
        return _validatorsMap[account].status != ValidatorStatus.NotFound;
    }

    function getValidators() external view returns (address[] memory) {
        (address[] memory validators,) = _getValidatorsWithVotingKeys();
        return validators;
    }

    function _getValidatorsWithVotingKeys() internal view returns (address[] memory, bytes[] memory) {
        uint256 n = _activeValidatorsList.length;
        address[] memory orderedValidators = new address[](n);
        for (uint256 i = 0; i < n; i++) {
            orderedValidators[i] = _activeValidatorsList[i];
        }
        // we need to select k top validators out of n
        uint256 k = _STAKING_CONFIG_CONTRACT.getActiveValidatorsLength();
        if (k > n) {
            k = n;
        }
        for (uint256 i = 0; i < k; i++) {
            uint256 nextValidator = i;
            Validator memory currentMax = _validatorsMap[orderedValidators[nextValidator]];
            ValidatorSnapshot memory maxSnapshot = _validatorSnapshots[currentMax.validatorAddress][currentMax.changedAt];
            for (uint256 j = i + 1; j < n; j++) {
                Validator memory current = _validatorsMap[orderedValidators[j]];
                ValidatorSnapshot memory currentSnapshot = _validatorSnapshots[current.validatorAddress][current.changedAt];
                if (maxSnapshot.totalDelegated < currentSnapshot.totalDelegated) {
                    nextValidator = j;
                    currentMax = current;
                    maxSnapshot = currentSnapshot;
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
        bytes[] memory votingKeys = new bytes[](k);
        for (uint256 i = 0; i < k; i++) {
            votingKeys[i] = _validatorsMap[orderedValidators[i]].votingKey;
        }
        return (orderedValidators, votingKeys);
    }

    function getLivingValidators() external view returns (address[] memory, bytes[] memory) {
        return _getValidatorsWithVotingKeys();
    }

    function getMiningValidators() external view returns (address[] memory, bytes[] memory) {
        return _getValidatorsWithVotingKeys();
    }

    function deposit(address validatorAddress) external payable onlyFromCoinbase virtual override {
        // value must be specified
        require(msg.value > 0);
        // deposit fee for the specific validator
        _depositFee(validatorAddress, msg.value);
    }

    function _depositFee(address validatorAddress, uint256 amount) internal {
        // make sure validator is active
        Validator memory validator = _validatorsMap[validatorAddress];
        require(validator.status != ValidatorStatus.NotFound, "not found");
        uint64 epoch = _currentEpoch();
        // increase total pending rewards for validator for current epoch
        ValidatorSnapshot storage currentSnapshot = _touchValidatorSnapshot(validator, epoch);
        currentSnapshot.totalRewards += uint96(amount);
        // emit event
        emit ValidatorDeposited(validatorAddress, amount, epoch);
    }

    function _slashValidator(address validatorAddress) internal {
        // make sure validator exists
        Validator memory validator = _validatorsMap[validatorAddress];
        require(validator.status != ValidatorStatus.NotFound, "not found");
        uint64 epoch = _currentEpoch();
        // increase slashes for current epoch
        ValidatorSnapshot storage currentSnapshot = _touchValidatorSnapshot(validator, epoch);
        uint32 slashesCount = currentSnapshot.slashesCount + 1;
        currentSnapshot.slashesCount = slashesCount;
        // if validator has a lot of misses then put it in jail for 1 week (if epoch is 1 day)
        if (slashesCount == _STAKING_CONFIG_CONTRACT.getFelonyThreshold()) {
            validator.jailedBefore = _currentEpoch() + _STAKING_CONFIG_CONTRACT.getValidatorJailEpochLength();
            validator.status = ValidatorStatus.Jail;
            _removeValidatorFromActiveList(validatorAddress);
            _validatorsMap[validatorAddress] = validator;
            emit ValidatorJailed(validatorAddress, epoch);
        } else {
            // validator state might change, lets update it
            _validatorsMap[validatorAddress] = validator;
        }
        // emit event
        emit ValidatorSlashed(validatorAddress, slashesCount, epoch);
    }
}