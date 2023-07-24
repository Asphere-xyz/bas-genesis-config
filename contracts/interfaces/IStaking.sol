// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "./IStakingValidatorRegistry.sol";
import "./IStakingRewardDistribution.sol";

interface IStaking is IStakingValidatorRegistry, IStakingRewardDistribution {
}