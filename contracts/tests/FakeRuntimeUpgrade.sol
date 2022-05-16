// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "../RuntimeUpgrade.sol";

contract FakeRuntimeUpgrade is RuntimeUpgrade {

    constructor(bytes memory constructorParams) RuntimeUpgrade(constructorParams) {
    }

    function upgradeSystemSmartContract(
        address systemContractAddress,
        bytes calldata newByteCode,
        bytes calldata applyFunction
    ) external override {
        _upgradeSystemSmartContract(systemContractAddress, newByteCode, applyFunction, IRuntimeUpgradeEvmHook.upgradeTo.selector);
    }

    function deploySystemSmartContract(
        address systemContractAddress,
        bytes calldata newByteCode,
        bytes calldata applyFunction
    ) external virtual override {
        _upgradeSystemSmartContract(systemContractAddress, newByteCode, applyFunction, IRuntimeUpgradeEvmHook.deployTo.selector);
        _deployedSystemContracts.push(systemContractAddress);
    }
}