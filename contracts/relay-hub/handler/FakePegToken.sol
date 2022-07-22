// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.6;

import "./ERC20PegToken.sol";

contract FakePegToken is ERC20PegToken {

    constructor() ERC20PegToken() {
    }

    modifier onlyCrossChainBridge() override {
        _;
    }
}