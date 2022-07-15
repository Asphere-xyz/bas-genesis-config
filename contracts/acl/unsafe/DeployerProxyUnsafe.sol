// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "../DeployerProxy.sol";

contract DeployerProxyUnsafe is DeployerProxy {

    constructor(ConstructorArguments memory constructorArgs) DeployerProxy(constructorArgs) {
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