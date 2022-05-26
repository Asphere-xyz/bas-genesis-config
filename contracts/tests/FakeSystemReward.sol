// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "../SystemReward.sol";

contract FakeSystemReward is SystemReward {

    constructor(
        IStaking stakingContract,
        ISlashingIndicator slashingIndicatorContract,
        ISystemReward systemRewardContract,
        IStakingPool stakingPoolContract,
        IGovernance governanceContract,
        IChainConfig chainConfigContract,
        IRuntimeUpgrade runtimeUpgradeContract,
        IDeployerProxy deployerProxyContract
    ) SystemReward(
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

    modifier onlyFromCoinbase() virtual override {
        _;
    }

    modifier onlyFromSlashingIndicator() virtual override {
        _;
    }

    modifier onlyFromGovernance() virtual override {
        _;
    }

    modifier onlyFromRuntimeUpgrade() virtual override {
        _;
    }

    modifier onlyZeroGasPrice() virtual override {
        _;
    }
}