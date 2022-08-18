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

    StakingValidatorRegistry private immutable _validatorRegistryLib;
    StakingRewardDistribution private immutable _rewardDistributionLib;

    constructor(IStakingConfig stakingConfig, StakingParams memory stakingParams) StakingStorageLayout(stakingConfig, stakingParams) {
        _validatorRegistryLib = new StakingValidatorRegistry(stakingConfig, stakingParams);
        _rewardDistributionLib = new StakingRewardDistribution(stakingConfig, stakingParams);
    }

    function _fallback() internal virtual override {
        // try both of addresses
        _delegate(address(_validatorRegistryLib));
        _delegate(address(_rewardDistributionLib));
        // revert if not found
        revert MethodNotFound();
    }
}