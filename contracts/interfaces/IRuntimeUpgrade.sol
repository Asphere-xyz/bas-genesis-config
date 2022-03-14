// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

interface IRuntimeUpgrade {

    event RuntimeUpgrade(address systemContractAddress, bytes newByteCode);

    function upgradeSystemSmartContract(address systemContractAddress, bytes calldata newByteCode, bytes calldata applyFunction) external;
}