// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "../interfaces/ICrossChainBridge.sol";

interface ITokenFactory {

    function getImplementation() external view returns (address);
}