// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "./Injector.sol";

abstract contract Staking is IParlia, IStaking {

    uint256 public constant MISDEMEANOR_THRESHOLD = 50;
    uint256 public constant FELONY_THRESHOLD = 150;

    uint32 public constant DEFAULT_ACTIVE_VALIDATORS_SIZE = 22;
    /**
     * Frequency of reward distribution and validator refresh
     */
    uint256 public constant DISTRIBUTE_DELEGATION_REWARDS_BLOCK_INTERVAL = 24 * 60 * 60 / 3; // 1 hour
    uint256 public constant COMMIT_INCOMING_BLOCK_INTERVAL = 1 * 60 * 60 / 3; // 1 day
    uint256 public constant VALIDATOR_UNDELEGATE_LOCK_PERIOD = 7 * 24 * 60 * 60 / 3; // 7 days

    event ValidatorAdded(address validator);
    event ValidatorRemoved(address validator);
    event ValidatorSlashed(address validator, uint32 slashes);
    event Delegated(address validator, address from, uint256 amount);
    event Undelegated(address validator, address from, uint256 amount);

    enum ValidatorStatus {
        NotFound,
        Alive,
        Pending,
        Jail
    }

    /**
     * Delegation structure:
     *  - delegatedAmount - total delegated balance to the single validator
     *  - unstakeBlockedBefore - after this block user can withdraw his pending undelegated amount
     *  - pendingUnstake - pending undelegate amount from this validator
     */
    struct Delegation {
        uint256 delegatedAmount;
        uint64 unstakeBlockedBefore;
        uint256 pendingUndelegate;
    }

    /**
     * Validator structure indicates information about validator and it's status:
     *  - validatorOwner - validator owner, he can initiate exit and claim fees
     *  - status - status of validator
     *  - commissionRate - validator's commission rate that is claimed by owner
     *  - totalSlashes - total missed block by validators in COMMIT_INCOMING_BLOCK_INTERVAL interval
     *  - confirmedBalance - total confirmed balance for reward distribution
     *  - pendingBalance - pending validator rewards for last one hour
     *  - claimableBalance - indicating how much owner can claim from commission
     *  - delegations - list of all delegations to this validator
     *  - totalDelegated - total delegated amount to this validator
     */
    struct Validator {
        address validatorOwner;
        ValidatorStatus status;
        uint256 commissionRate;
        uint32 totalSlashes;
        uint256 confirmedBalance;
        uint256 pendingBalance;
        uint256 claimableBalance;
        mapping(address => uint256) delegatorsMap;
        Delegation[] delegations;
        uint256 totalDelegated;
    }

    uint32 internal _consensusLimit;
    mapping(address => Validator) internal _validatorsMap;
    address[] internal _validators;
    uint64 internal _recentRewardDistribution;
    uint64 internal _recentSlashAndRewardDistribution;
    uint256 internal _systemFee;

    function delegate(address validatorAddress) payable external override {
        _delegateTo(msg.sender, validatorAddress, msg.value);
    }

    function _delegateTo(address fromAddress, address toValidator, uint256 amount) internal {
        require(amount >= 1 ether, "Staking: min staking amount is 1 ether");
        Validator storage validator = _validatorsMap[toValidator];
        require(validator.status == ValidatorStatus.Alive, "Staking: validator is not active");
        uint256 delegatorOffset = validator.delegatorsMap[fromAddress];
        if (delegatorOffset == 0) {
            validator.delegations.push(Delegation({delegatedAmount : amount, unstakeBlockedBefore : 0, pendingUndelegate : 0}));
            validator.delegatorsMap[fromAddress] = validator.delegations.length - 1;
        } else {
            validator.delegations[delegatorOffset].delegatedAmount += amount;
        }
        validator.totalDelegated += amount;
        emit Delegated(toValidator, fromAddress, amount);
    }

    function getValidatorDelegation(address validatorAddress, address delegator) external view override returns (
        uint256 delegatedAmount,
        uint64 unstakeBlockedBefore,
        uint256 pendingUndelegate
    ) {
        Validator storage validator = _validatorsMap[validatorAddress];
        uint256 delegatorOffset = validator.delegatorsMap[delegator];
        if (delegatorOffset > 0 && delegatorOffset < validator.delegations.length) {
            delegatedAmount = validator.delegations[delegatorOffset].delegatedAmount;
            unstakeBlockedBefore = validator.delegations[delegatorOffset].unstakeBlockedBefore;
            pendingUndelegate = validator.delegations[delegatorOffset].pendingUndelegate;
        } else {
            delegatedAmount = 0;
            unstakeBlockedBefore = 0;
            pendingUndelegate = 0;
        }
    }

    function getValidatorDelegations(address validatorAddress) external view override returns (
        uint8 status,
        uint256 delegated
    ) {
        Validator storage validator = _validatorsMap[validatorAddress];
        status = uint8(validator.status);
        delegated = validator.totalDelegated;
    }

    function undelegate(address validatorAddress, uint256 amount) payable external override {
        revert("not supported");
    }

    function _addValidator(address account, address owner) internal {
        require(_validatorsMap[account].status == ValidatorStatus.NotFound, "Staking: validator already exist");
        Validator storage validator = _validatorsMap[account];
        validator.validatorOwner = owner;
        validator.status = ValidatorStatus.Alive;
        validator.delegations.push(Delegation({
        delegatedAmount : 0,
        unstakeBlockedBefore : 0,
        pendingUndelegate : 0
        }));
        _validators.push(account);
        emit ValidatorAdded(account);
    }

    function _removeValidator(address account) internal {
        require(_validatorsMap[account].status != ValidatorStatus.NotFound, "Staking: validator not found");
        // find index of validator in validator set
        int256 indexOf = - 1;
        for (uint256 i = 0; i < _validators.length; i++) {
            if (_validators[i] != account) continue;
            indexOf = int256(i);
            break;
        }
        require(indexOf >= 0, "Staking: validator not found");
        // remove validator from array
        if (_validators.length > 1 && uint256(indexOf) != _validators.length - 1) {
            _validators[uint256(indexOf)] = _validators[_validators.length - 1];
        }
        _validators.pop();
        // remove from validators map
        delete _validatorsMap[account];
        emit ValidatorRemoved(account);
    }

    function isValidator(address account) external override view returns (bool) {
        return _validatorsMap[account].status != ValidatorStatus.NotFound;
    }

    function getValidators() external view override returns (address[] memory) {
        uint64 activeValidatorsLimit = _consensusLimit;
        if (activeValidatorsLimit == 0) {
            activeValidatorsLimit = DEFAULT_ACTIVE_VALIDATORS_SIZE;
        }
        address[] memory activeValidators;
        if (_validators.length >= activeValidatorsLimit) {
            activeValidators = new address[](activeValidatorsLimit);
        } else {
            activeValidators = new address[](_validators.length);
        }
        // sort validators
        address[] memory orderedValidators = new address[](_validators.length);
        for (uint256 i = 0; i < _validators.length; i++) {
            orderedValidators[i] = _validators[i];
        }
        for (uint256 i = 0; i < orderedValidators.length; i++) {
            Validator storage left = _validatorsMap[orderedValidators[i]];
            for (uint256 j = i + 1; j < orderedValidators.length; j++) {
                Validator storage right = _validatorsMap[orderedValidators[j]];
                if (left.totalDelegated > right.totalDelegated) {
                    continue;
                }
                (orderedValidators[i], orderedValidators[j]) = (orderedValidators[j], orderedValidators[i]);
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
        Validator storage validator = _validatorsMap[validatorAddress];
        require(validator.status == ValidatorStatus.Alive, "Staking: validator not active");
        validator.pendingBalance += msg.value;
        // commit pending validator rewards once per hour and distribute committed rewards between delegators
        _slashValidatorsAndConfirmRewards();
        _distributeValidatorRewards(validator);
    }

    function claimDepositFee(address payable validatorAddress) external override {
        _claimDepositFee(validatorAddress);
    }

    function _claimDepositFee(address payable validatorAddress) internal {
        Validator storage validator = _validatorsMap[validatorAddress];
        uint256 totalFee = validator.confirmedBalance;
        require(totalFee > 0, "Staking: deposited fee is zero");
        validator.confirmedBalance = 0;
        require(validatorAddress.send(totalFee), "Staking: transfer failed");
    }

    function _slashValidatorsAndConfirmRewards() internal {
        // do it only once some interval
        if (block.number < _recentSlashAndRewardDistribution + COMMIT_INCOMING_BLOCK_INTERVAL) {
            return;
        }
        uint256 totalSlashedIncome = 0;
        uint256 goodValidators = 0;
        // calculate average slashing payout from all slashed validators, we think that
        // validator is slashed if validator has at least one block miss.
        for (uint256 i = 0; i < _validators.length; i++) {
            Validator storage validator = _validatorsMap[_validators[i]];
            if (validator.totalSlashes > 0) {
                totalSlashedIncome += validator.pendingBalance;
            } else {
                goodValidators++;
            }
        }
        // if there is no not slashed validators then something wrong with network at all,
        // but of course it will never happen. the best we can do in such situation is just to
        // exit and do nothing here.
        if (goodValidators == 0) {
            return;
        }
        // distribute total slashed balance between honest validators and pay
        // all dust to the system
        uint256 averageSlashingPayout = totalSlashedIncome / goodValidators;
        for (uint256 i = 0; i < _validators.length; i++) {
            Validator storage validator = _validatorsMap[_validators[i]];
            if (validator.totalSlashes > 0) {
                continue;
            }
            validator.pendingBalance += averageSlashingPayout;
        }
        uint256 distributionDust = totalSlashedIncome - averageSlashingPayout * goodValidators;
        _systemFee += distributionDust;
        // confirm pending validator rewards and reset slashing state
        for (uint256 i = 0; i < _validators.length; i++) {
            Validator storage validator = _validatorsMap[_validators[i]];
            if (validator.totalSlashes > 0) {
                // for slashed validator lets just reset all his stats and
                // let him start again, probably its better to put this validator in jail
                // for some period of time
                validator.totalSlashes = 0;
                validator.pendingBalance = 0;
            } else {
                // move pending validator's balance to confirmed, it means that now validator
                // can distribute this rewards between delegates
                validator.confirmedBalance += validator.pendingBalance;
                validator.pendingBalance = 0;
            }
        }
        // update latest reward commit block
        _recentSlashAndRewardDistribution = uint64(block.number);
    }

    function _distributeValidatorRewards(Validator storage validator) internal {
        // do it only once some interval
        if (block.number < _recentRewardDistribution + DISTRIBUTE_DELEGATION_REWARDS_BLOCK_INTERVAL) {
            return;
        }
        uint256 ownerShare = validator.commissionRate * validator.confirmedBalance / 1e18;
        uint256 delegatorsShare = validator.confirmedBalance - ownerShare;
        for (uint256 i = 0; i < validator.delegations.length; i++) {
            Delegation storage delegation = validator.delegations[i];
            uint256 share = delegatorsShare * delegation.delegatedAmount / validator.totalDelegated;
            delegation.delegatedAmount += share;
            validator.delegations[i] = delegation;
        }
        // update latest reward distribution block
        _recentRewardDistribution = uint64(block.number);
    }

    function _slashValidator(address validatorAddress) internal {
        Validator storage validator = _validatorsMap[validatorAddress];
        require(validator.status == ValidatorStatus.Alive, "Staking: validator not found");
        validator.totalSlashes++;
        emit ValidatorSlashed(validatorAddress, validator.totalSlashes);
    }

    receive() external payable {
        _systemFee += msg.value;
    }
}
