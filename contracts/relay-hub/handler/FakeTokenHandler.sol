// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.6;

import "./ERC20TokenHandler.sol";
import "./FakePegToken.sol";

contract FakeTokenHandler is ERC20TokenHandler {

    constructor() ERC20TokenHandler() {
    }

    function _factoryTokenTemplate() internal override returns (address) {
        return address(new FakePegToken());
    }
}