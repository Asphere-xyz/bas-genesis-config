// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.6;

import "./ICrossChainBridge.sol";

interface IBridgeHandler {

    function calcPegTokenAddress(address bridgeAddress, address fromToken) external view returns (address);

    function factoryPegToken(address fromToken, ICrossChainBridge.MetaData memory metaData, uint256 fromChain) external returns (address);
}
