// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "../Staking.sol";

contract FakeStaking is Staking {

    constructor(
        IStaking stakingContract,
        ISlashingIndicator slashingIndicatorContract,
        ISystemReward systemRewardContract,
        IStakingPool stakingPoolContract,
        IGovernance governanceContract,
        IChainConfig chainConfigContract,
        IRuntimeUpgrade runtimeUpgradeContract,
        IDeployerProxy deployerProxyContract
    ) Staking(
        stakingContract,
        slashingIndicatorContract,
        systemRewardContract,
        stakingPoolContract,
        governanceContract,
        chainConfigContract,
        runtimeUpgradeContract,
        deployerProxyContract
    ) {
    }

    function addValidator(address account) external override {
        _addValidator(account, account, ValidatorStatus.Active, 0, 0, _nextEpoch());
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