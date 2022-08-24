// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "./interfaces/IStaking.sol";
import "../InjectorContextHolder.sol";
import "../staking/AbstractStakingPool.sol";

contract StakingPool is InjectorContextHolder, AbstractStakingPool {

    constructor(ConstructorArguments memory constructorArgs) InjectorContextHolder(constructorArgs) AbstractStakingPool(constructorArgs.chainConfigContract, constructorArgs.stakingContract) {
    }

    function initialize() external initializer {
    }
}