// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "./Injector.sol";

contract SlashingIndicator is ISlashingIndicator, InjectorContextHolder {

    constructor() {
    }

    function slash(address validator) external onlyFromCoinbase onlyOncePerBlock virtual override {
        // we need this proxy to be compatible with BSC
        _stakingContract.slash(validator);
    }
}