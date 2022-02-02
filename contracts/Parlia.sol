// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "./Staking.sol";

contract Parlia is Staking, InjectorContextHolderV1 {

    constructor(address[] memory validators) {
        for (uint256 i = 0; i < validators.length; i++) {
            _addValidator(validators[i], validators[i]);
        }
    }

    function addValidator(address account) external onlyFromGovernance override {
        _addValidator(account, account);
    }

    function removeValidator(address account) external onlyFromGovernance override {
        _removeValidator(account);
    }

    function deposit(address validatorAddress) external payable onlyFromCoinbase onlyZeroGasPrice override {
        _depositFee(validatorAddress);
    }

    function slash(address validatorAddress) external onlyFromCoinbase onlyZeroGasPrice onlyOncePerBlock override {
        _slashValidator(validatorAddress);
    }
}