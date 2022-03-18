// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "./Injector.sol";

contract RuntimeUpgrade is InjectorContextHolder, IRuntimeUpgrade {

    constructor(bytes memory ctor) InjectorContextHolder(ctor) {
    }

    function initialize() external whenNotInitialized {
    }

    function upgradeSystemSmartContract(
        address systemContractAddress,
        bytes memory newByteCode,
        bytes calldata applyFunction
    ) external onlyFromGovernance {
        IInjector injector = IInjector(systemContractAddress);
        // emit special runtime upgrade event that modifies bytecode
        emit RuntimeUpgrade(systemContractAddress, newByteCode);
        // if this is new smart contract then run "init" function
        if (!injector.isInitialized()) {
            injector.init();
        }
        // call migration function if specified
        if (applyFunction.length > 0) {
            (bool result,) = systemContractAddress.call(applyFunction);
            require(result, "RuntimeUpgrade: migration failed");
        }
    }
}