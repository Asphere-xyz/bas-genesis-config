// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "./Staking.sol";

contract FakeStaking is Staking, InjectorContextHolderV1 {

    function addValidator(address account) external override {
        _addValidator(account, account);
    }

    function removeValidator(address account) external override {
        _removeValidator(account);
    }

    function deposit(address validatorAddress) external payable override {
        _depositFee(validatorAddress);
    }

    function slash(address validatorAddress) external override {
        _slashValidator(validatorAddress);
    }
}