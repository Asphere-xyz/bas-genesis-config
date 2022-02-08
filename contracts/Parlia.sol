// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "./Staking.sol";

contract Parlia is Staking, InjectorContextHolderV1 {

    constructor(address[] memory validators) {
        for (uint256 i = 0; i < validators.length; i++) {
            _addValidator(validators[i], validators[i], ValidatorStatus.Alive, 0, 0);
        }
    }

    function addValidator(address account) external onlyFromGovernance override {
        _addValidator(account, account, ValidatorStatus.Alive, 0, 0);
    }

    function removeValidator(address account) external onlyFromGovernance override {
        _removeValidator(account);
    }

    function activateValidator(address validator) external onlyFromGovernance override {
        _activateValidator(validator);
    }

    function disableValidator(address validator) external onlyFromGovernance override {
        _disableValidator(validator);
    }

    function deposit(address validatorAddress) external payable onlyFromCoinbase onlyZeroGasPrice override {
        _depositFee(validatorAddress);
    }

    function slash(address validatorAddress) external onlyFromCoinbase onlyZeroGasPrice onlyOncePerBlock override {
        _slashValidator(validatorAddress);
    }
}