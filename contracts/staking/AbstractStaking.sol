// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "./libs/StakingValidatorRegistry.sol";
import "./libs/StakingRewardDistribution.sol";

import "../common/RetryableProxy.sol";

/**
 * You might ask why this library model is so overcomplicated... the answer is that we tried
 * to keep backward compatibility with existing storage layout when smart contract size become more than 24kB.
 *
 * Since this checks works only for deployed smart contracts (not constructors) then we can deploy several
 * smart contracts with more than 24kB size.
 */
abstract contract AbstractStaking is StakingStorageLayout, RetryableProxy {

    StakingValidatorRegistry internal immutable _validatorRegistryLib;
    StakingRewardDistribution internal immutable _rewardDistributionLib;

    constructor(
        IStakingConfig stakingConfig,
        StakingParams memory stakingParams,
        StakingValidatorRegistry validatorRegistry,
        StakingRewardDistribution rewardDistribution
    ) StakingStorageLayout(stakingConfig, stakingParams) {
        _validatorRegistryLib = validatorRegistry;
        _rewardDistributionLib = rewardDistribution;
    }

    function _fallback() internal virtual override {
        // try both of addresses
        _delegate(address(_validatorRegistryLib));
        _delegate(address(_rewardDistributionLib));
        // revert if not found
        revert MethodNotFound();
    }
}

contract SimpleStaking is AbstractStaking {

    constructor(IStakingConfig stakingConfig, StakingParams memory stakingParams)
    AbstractStaking(stakingConfig, stakingParams,
        new StakingValidatorRegistry(stakingConfig, stakingParams),
        new StakingRewardDistribution(stakingConfig, stakingParams)
    ) {
    }
}