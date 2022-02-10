// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "./Staking.sol";

contract FakeStaking is Staking, InjectorContextHolderV1 {

    constructor(
        address systemTreasury,
        uint32 activeValidatorsLength,
        uint32 epochBlockInterval,
        uint32 misdemeanorThreshold,
        uint32 felonyThreshold,
        uint32 validatorJailEpochLength
    ) {
        // system params
        _consensusParams.activeValidatorsLength = activeValidatorsLength;
        _consensusParams.epochBlockInterval = epochBlockInterval;
        _consensusParams.misdemeanorThreshold = misdemeanorThreshold;
        _consensusParams.felonyThreshold = felonyThreshold;
        _consensusParams.validatorJailEpochLength = validatorJailEpochLength;
        // treasury
        _systemTreasury = systemTreasury;
    }

    function addValidator(address account) external override {
        _addValidator(account, account, ValidatorStatus.Alive, 0, 0);
    }

    function removeValidator(address account) external override {
        _removeValidator(account);
    }

    function activateValidator(address validator) external override {
        _activateValidator(validator);
    }

    function disableValidator(address validator) external override {
        _disableValidator(validator);
    }

    function deposit(address validatorAddress) external payable override {
        _depositFee(validatorAddress);
    }

    function slash(address validatorAddress) external override {
        _slashValidator(validatorAddress);
    }
}