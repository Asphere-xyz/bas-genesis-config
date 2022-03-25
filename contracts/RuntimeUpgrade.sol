// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "./Injector.sol";

contract RuntimeUpgrade is InjectorContextHolder, IRuntimeUpgrade {

    event SmartContractUpgrade(address contractAddress, bytes newByteCode);

    address internal _evmHookAddress;

    constructor(bytes memory constructorParams) InjectorContextHolder(constructorParams) {
    }

    function ctor(address evmHookAddress) external whenNotInitialized {
        _evmHookAddress = evmHookAddress;
    }

    function upgradeSystemSmartContract(
        address systemContractAddress,
        bytes calldata newByteCode,
        bytes calldata applyFunction
    ) external onlyFromGovernance virtual override {
        _upgradeSystemSmartContract(systemContractAddress, newByteCode, applyFunction);
    }

    function _upgradeSystemSmartContract(
        address systemContractAddress,
        bytes calldata newByteCode,
        bytes calldata applyFunction
    ) internal {
        // emit special runtime upgrade event that modifies bytecode
        require(_isSystemSmartContract(systemContractAddress), "RuntimeUpgrade: only system smart contract");
        IRuntimeUpgradeEvmHook(_evmHookAddress).upgradeTo(systemContractAddress, newByteCode);
        // if this is new smart contract then run "init" function
        IInjector injector = IInjector(systemContractAddress);
        if (!injector.isInitialized()) {
            injector.init();
        }
        // call migration function if specified
        if (applyFunction.length > 0) {
            (bool result,) = systemContractAddress.call(applyFunction);
            require(result, "RuntimeUpgrade: migration failed");
        }
        // emit event
        emit SmartContractUpgrade(systemContractAddress, newByteCode);
    }

    function getEvmHookAddress() external view returns (address) {
        return _evmHookAddress;
    }
}