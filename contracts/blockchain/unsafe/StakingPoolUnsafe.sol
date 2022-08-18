// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "../StakingPool.sol";

contract StakingPoolUnsafe is StakingPool {

    constructor(ConstructorArguments memory constructorArgs) StakingPool(constructorArgs) {
    }
}