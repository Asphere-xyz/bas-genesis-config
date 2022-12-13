// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "./IStakingRewardDistribution.sol";
import "./IStakingValidatorRegistry.sol";

interface IStaking is IStakingRewardDistribution, IStakingValidatorRegistry {
}