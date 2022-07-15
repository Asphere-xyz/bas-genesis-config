// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "./StakingUnsafe.sol";

contract StakingWithMethodUnsafe is StakingUnsafe {

    constructor(
        IStaking stakingContract,
        ISlashingIndicator slashingIndicatorContract,
        ISystemReward systemRewardContract,
        IStakingPool stakingPoolContract,
        IGovernance governanceContract,
        IStakingConfig chainConfigContract,
        IRuntimeUpgrade runtimeUpgradeContract,
        IDeployerProxy deployerProxyContract
    ) StakingUnsafe(
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

    function thisIsMethod() external pure returns (uint256) {
        return 0x7b;
    }
}