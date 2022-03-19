// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "./Injector.sol";

interface IRuntimeUpgradeEvmHook {
    function upgradeTo(address contractAddress, bytes calldata byteCode) external;
}

contract RuntimeUpgrade is InjectorContextHolder, IRuntimeUpgrade {

    address constant internal EVM_HOOK_RUNTIME_UPGRADE_ADDRESS = 0x0000000000000000000000000000000000007f01;

    event SmartContractUpgrade(address contractAddress, bytes newByteCode);

    constructor(bytes memory constructorParams) InjectorContextHolder(constructorParams) {
    }

    function ctor() external whenNotInitialized {
    }

    function upgradeSystemSmartContract(
        address systemContractAddress,
        bytes memory newByteCode,
        bytes calldata applyFunction
    ) external onlyFromGovernance {
        IInjector injector = IInjector(systemContractAddress);
        // emit special runtime upgrade event that modifies bytecode
        require(_isSystemSmartContract(systemContractAddress), "RuntimeUpgrade: only system smart contract");
        IRuntimeUpgradeEvmHook(EVM_HOOK_RUNTIME_UPGRADE_ADDRESS).upgradeTo(systemContractAddress, newByteCode);
        // if this is new smart contract then run "init" function
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
}