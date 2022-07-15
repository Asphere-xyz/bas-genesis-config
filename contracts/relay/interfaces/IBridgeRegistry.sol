// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

interface IBridgeRegistry {

    function getBridgeAddress(uint256 chainId) external view returns (address);
}