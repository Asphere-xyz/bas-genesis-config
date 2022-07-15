// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "../StakingConfig.sol";

contract StakingConfigUnsafe is StakingConfig {

    constructor(
        IStaking stakingContract,
        ISlashingIndicator slashingIndicatorContract,
        ISystemReward systemRewardContract,
        IStakingPool stakingPoolContract,
        IGovernance governanceContract,
        IStakingConfig chainConfigContract,
        IRuntimeUpgrade runtimeUpgradeContract,
        IDeployerProxy deployerProxyContract
    ) StakingConfig(
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

    modifier onlyFromCoinbase() override {
        _;
    }

    modifier onlyFromSlashingIndicator() override {
        _;
    }

    modifier onlyFromGovernance() override {
        _;
    }

    modifier onlyBlock(uint64 /*blockNumber*/) override {
        _;
    }
}