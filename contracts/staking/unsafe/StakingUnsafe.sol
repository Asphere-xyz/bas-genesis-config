// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "../libs/StakingValidatorRegistry.sol";
import "../libs/StakingRewardDistribution.sol";

contract StakingValidatorRegistryUnsafe is StakingValidatorRegistry {

    constructor(ConstructorArguments memory constructorArgs) StakingValidatorRegistry(constructorArgs) {
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

    constructor(ConstructorArguments memory constructorArgs) StakingRewardDistribution(constructorArgs) {
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

    constructor(ConstructorArguments memory constructorArgs) InjectorContextHolder(constructorArgs) {
        _validatorRegistryLib = new StakingValidatorRegistryUnsafe(constructorArgs);
        _rewardDistributionLib = new StakingRewardDistributionUnsafe(constructorArgs);
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