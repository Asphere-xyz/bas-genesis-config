// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "../CrossChainBridge.sol";

contract TestCrossChainBridge is CrossChainBridge {

    function _checkContractAllowed(ReceiptParser.State memory state) internal view virtual override {
        // don't do this check for test because we don't have bridge address list
    }
}