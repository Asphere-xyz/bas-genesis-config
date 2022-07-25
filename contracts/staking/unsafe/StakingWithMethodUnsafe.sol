// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "./StakingUnsafe.sol";

contract StakingWithMethodUnsafe is StakingUnsafe {

    constructor(ConstructorArguments memory constructorArgs) StakingUnsafe(constructorArgs) {
    }

    function thisIsMethod() external pure returns (uint256) {
        return 0x7b;
    }
}