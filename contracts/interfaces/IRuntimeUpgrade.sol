// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

interface IRuntimeUpgrade {

    function isEIP1967() external view returns (bool);

    function upgradeSystemSmartContract(address payable account, bytes calldata bytecode, bytes calldata data) external payable;

    function deploySystemSmartContract(address payable account, bytes calldata bytecode, bytes calldata data) external payable;
}