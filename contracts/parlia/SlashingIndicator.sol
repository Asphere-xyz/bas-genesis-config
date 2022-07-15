// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "../InjectorContextHolder.sol";

contract SlashingIndicator is InjectorContextHolder, ISlashingIndicator {

    constructor(ConstructorArguments memory constructorArgs) InjectorContextHolder(constructorArgs) {
    }

    function initialize() external initializer {
    }

    function slash(address validator) external onlyFromCoinbase virtual override {
        // we need this proxy to be compatible with BSC
        _STAKING_CONTRACT.slash(validator);
    }
}