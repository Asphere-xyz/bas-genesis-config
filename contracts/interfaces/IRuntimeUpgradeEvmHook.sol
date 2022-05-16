// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

interface IRuntimeUpgradeEvmHook {

    function upgradeTo(address contractAddress, bytes calldata byteCode) external;

    function deployTo(address contractAddress, bytes calldata byteCode) external;
}