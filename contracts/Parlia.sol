// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "./Injector.sol";

contract Parlia is IParlia, InjectorContextHolderV1 {

    uint256 public constant MISDEMEANOR_THRESHOLD = 50;
    uint256 public constant FELONY_THRESHOLD = 150;

    uint256 public constant ACTIVE_VALIDATORS_SIZE = 21;
    /**
     * Frequency of reward distribution and validator refresh
     */
    uint256 public constant DISTRIBUTE_DELEGATION_REWARDS_BLOCK_INTERVAL = 24 * 60 * 60 / 3; // 1 hour
    uint256 public constant COMMIT_INCOMING_BLOCK_INTERVAL = 1 * 60 * 60 / 3; // 1 day
    uint256 public constant VALIDATOR_UNDELEGATE_LOCK_PERIOD = 7 * 24 * 60 * 60 / 3; // 7 days

    event ValidatorAdded(address account);
    event ValidatorRemoved(address account);

    enum ValidatorStatus {
        NotFound,
        Active,
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
     *  - owner - validator owner, he can initiate exit and claim fees
     *  - status - status of validator
     *  - commission - validator's commission rate that is claimed by owner
     *  - slashes - total missed block by validators in COMMIT_INCOMING_BLOCK_INTERVAL interval
     *  - confirmed - total confirmed balance for reward distribution
     *  - pending - pending validator rewards for last one hour
     *  - claimable - indicating how much owner can claim from commission
     *  - delegations - list of all delegations to this validator
     *  - delegated - total delegated amount to this validator
     */
    struct Validator {
        address owner;
        ValidatorStatus status;
        uint256 commission;
        uint32 slashes;
        uint256 confirmed;
        uint256 pending;
        uint256 claimable;
        Delegation[] delegations;
        uint256 delegated;
    }

    mapping(address => Validator) private _validatorsMap;
    address[] private _validators;
    uint64 private _recentRewardDistribution;
    uint64 private _recentPayoutCommit;
    uint256 private _systemFee;

    constructor(address[] memory validators) {
        for (uint256 i = 0; i < validators.length; i++) {
            _addValidator(validators[i]);
        }
    }

    function isValidator(address account) public override view returns (bool) {
        return _validatorsMap[account].status != ValidatorStatus.NotFound;
    }

    function addValidator(address account) public onlyFromGovernance override {
        _addValidator(account);
    }

    function _addValidator(address account) internal {
        require(_validatorsMap[account].status == ValidatorStatus.NotFound, "Parlia: validator already exist");
        Validator storage validator = _validatorsMap[account];
        validator.owner = account;
        validator.status = ValidatorStatus.Active;
        _validators.push(account);
        emit ValidatorAdded(account);
    }

    function removeValidator(address account) public onlyFromGovernance override {
        require(_validatorsMap[account].status != ValidatorStatus.NotFound, "Parlia: validator not found");
        // find index of validator in validator set
        int256 indexOf = - 1;
        for (uint256 i = 0; i < _validators.length; i++) {
            if (_validators[i] != account) continue;
            indexOf = int256(i);
            break;
        }
        require(indexOf >= 0, "Parlia: validator not found");
        // remove validator from array
        if (_validators.length > 1 && uint256(indexOf) != _validators.length - 1) {
            _validators[uint256(indexOf)] = _validators[_validators.length - 1];
        }
        _validators.pop();
        // remove from validators map
        delete _validatorsMap[account];
        emit ValidatorRemoved(account);
    }

    function getValidators() external view override returns (address[] memory) {
        address[] memory activeValidators;
        if (_validators.length >= ACTIVE_VALIDATORS_SIZE) {
            activeValidators = new address[](ACTIVE_VALIDATORS_SIZE);
        } else {
            activeValidators = new address[](_validators.length);
        }

//        for (uint256 i = 0; i < activeValidators.length; i++) {
//            Validator storage validator = _validatorsMap[sortedValidators[i].validator];
//            if (validator.status != ValidatorStatus.Active) {
//                continue;
//            }
//            activeValidators[i] = _validators[i];
//        }
//        return activeValidators;
        return _validators;
    }

    function deposit(address validatorAddress) public payable onlyFromCoinbaseOrGovernance onlyZeroGasPrice override {
        require(msg.value > 0, "Parlia: deposit is zero");
        // make sure validator is active
        Validator storage validator = _validatorsMap[validatorAddress];
        require(validator.status == ValidatorStatus.Active, "Parlia: validator not active");
        validator.pending += msg.value;
        // commit pending validator rewards once per hour
        if (block.number >= _recentPayoutCommit + COMMIT_INCOMING_BLOCK_INTERVAL) {
            _slashValidatorsAndDistributeRewards();
        }
        // distribute committed rewards between delegators
        if (block.number >= _recentRewardDistribution + DISTRIBUTE_DELEGATION_REWARDS_BLOCK_INTERVAL) {
            _distributeValidatorRewards(validator);
        }
    }

    function _slashValidatorsAndDistributeRewards() internal {
        // calculate average slashing payout from all slashed validators, we think that
        // validator is slashed if validator has at least one block miss.
        uint256 totalSlashedIncome = 0;
        uint256 goodValidators = 0;
        for (uint256 i = 0; i < _validators.length; i++) {
            Validator memory validator = _validatorsMap[_validators[i]];
            if (validator.slashes > 0) {
                totalSlashedIncome += validator.pending;
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
            Validator memory validator = _validatorsMap[_validators[i]];
            if (validator.slashes > 0) {
                continue;
            }
            validator.pending += averageSlashingPayout;
        }
        uint256 distributionDust = totalSlashedIncome - averageSlashingPayout * goodValidators;
        _systemFee += distributionDust;
        // confirm pending validator rewards and reset slashing state
        for (uint256 i = 0; i < _validators.length; i++) {
            Validator memory validator = _validatorsMap[_validators[i]];
            if (validator.slashes > 0) {
                // for slashed validator lets just reset all his stats and
                // let him start again, probably its better to put this validator in jail
                // for some period of time
                validator.slashes = 0;
                validator.pending = 0;
            } else {
                // move pending validator's balance to confirmed, it means that now validator
                // can distribute this rewards between delegates
                validator.confirmed += validator.pending;
                validator.pending = 0;
            }
        }
        // update latest reward commit block
        _recentPayoutCommit = uint64(block.number);
    }

    function _distributeValidatorRewards(Validator storage validator) internal {
        uint256 ownerShare = validator.commission * validator.confirmed / 1e18;
        uint256 delegatorsShare = validator.confirmed - ownerShare;
        for (uint256 i = 0; i < validator.delegations.length; i++) {
            Delegation storage delegation = validator.delegations[i];
            uint256 share = delegatorsShare * delegation.delegatedAmount / validator.delegated;
            delegation.delegatedAmount += share;
            validator.delegations[i] = delegation;
        }
        // update latest reward distribution block
        _recentRewardDistribution = uint64(block.number);
    }

    function claimDepositFee(address payable validator) public override {
        //        Validator memory validator = _validatorsMap[validatorAddress];
        //        uint256 totalFee = validator.confirmed;
        //        require(totalFee > 0, "Parlia: deposited fee is zero");
        //        validator.confirmed = 0;
        //        require(validator.send(totalFee), "Parlia: transfer failed");
    }

    function slash(address validatorAddress) external onlyFromCoinbaseOrGovernance onlyZeroGasPrice onlyOncePerBlock override {
        Validator storage validator = _validatorsMap[validatorAddress];
        require(validator.status == ValidatorStatus.Active, "Parlia: validator not found");
        validator.slashes++;
    }

    receive() external payable {
        _systemFee += msg.value;
    }
}
