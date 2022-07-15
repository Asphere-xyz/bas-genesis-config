// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "../StakingPool.sol";

contract StakingPoolUnsafe is StakingPool {

    constructor(ConstructorArguments memory constructorArgs) StakingPool(constructorArgs) {
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

    modifier onlyBlock(uint64 /*blockNumber*/) override {
        _;
    }
}