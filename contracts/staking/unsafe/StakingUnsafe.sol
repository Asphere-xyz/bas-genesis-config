// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "../libs/StakingValidatorRegistry.sol";
import "../libs/StakingRewardDistribution.sol";

contract StakingValidatorRegistryUnsafe is StakingValidatorRegistry {

    constructor(
        IStaking stakingContract,
        ISlashingIndicator slashingIndicatorContract,
        ISystemReward systemRewardContract,
        IStakingPool stakingPoolContract,
        IGovernance governanceContract,
        IStakingConfig chainConfigContract,
        IRuntimeUpgrade runtimeUpgradeContract,
        IDeployerProxy deployerProxyContract
    ) StakingValidatorRegistry(
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

    modifier onlyBlock(uint64 blockNumber) override {
        _;
    }
}

contract StakingRewardDistributionUnsafe is StakingRewardDistribution {

    constructor(
        IStaking stakingContract,
        ISlashingIndicator slashingIndicatorContract,
        ISystemReward systemRewardContract,
        IStakingPool stakingPoolContract,
        IGovernance governanceContract,
        IStakingConfig chainConfigContract,
        IRuntimeUpgrade runtimeUpgradeContract,
        IDeployerProxy deployerProxyContract
    ) StakingRewardDistribution(
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

    modifier onlyBlock(uint64 blockNumber) override {
        _;
    }
}

contract StakingUnsafe is StakingStorageLayout, RetryableProxy {

    StakingValidatorRegistryUnsafe private immutable _validatorRegistryLib;
    StakingRewardDistributionUnsafe private immutable _rewardDistributionLib;

    constructor(
        IStaking stakingContract,
        ISlashingIndicator slashingIndicatorContract,
        ISystemReward systemRewardContract,
        IStakingPool stakingPoolContract,
        IGovernance governanceContract,
        IStakingConfig chainConfigContract,
        IRuntimeUpgrade runtimeUpgradeContract,
        IDeployerProxy deployerProxyContract
    ) InjectorContextHolder(
        stakingContract,
        slashingIndicatorContract,
        systemRewardContract,
        stakingPoolContract,
        governanceContract,
        chainConfigContract,
        runtimeUpgradeContract,
        deployerProxyContract
    ) {
        _validatorRegistryLib = new StakingValidatorRegistryUnsafe(
            stakingContract,
            slashingIndicatorContract,
            systemRewardContract,
            stakingPoolContract,
            governanceContract,
            chainConfigContract,
            runtimeUpgradeContract,
            deployerProxyContract
        );
        _rewardDistributionLib = new StakingRewardDistributionUnsafe(
            stakingContract,
            slashingIndicatorContract,
            systemRewardContract,
            stakingPoolContract,
            governanceContract,
            chainConfigContract,
            runtimeUpgradeContract,
            deployerProxyContract
        );
    }

    function initialize(
        address[] calldata validators,
        bytes[] calldata votingKeys,
        address[] calldata owners,
        uint256[] calldata initialStakes,
        uint16 commissionRate
    ) external initializer {
        require(validators.length == owners.length && validators.length == initialStakes.length);
        uint256 totalStakes = 0;
        for (uint256 i = 0; i < validators.length; i++) {
            _addValidator(validators[i], votingKeys[i], owners[i], ValidatorStatus.Active, commissionRate, initialStakes[i], 0);
            totalStakes += initialStakes[i];
        }
        require(address(this).balance == totalStakes);
    }

    function _fallback() internal virtual override {
        // try both of addresses
        _delegate(address(_validatorRegistryLib));
        _delegate(address(_rewardDistributionLib));
        // revert if not found
        revert MethodNotFound();
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

    modifier onlyBlock(uint64 blockNumber) override {
        _;
    }
}