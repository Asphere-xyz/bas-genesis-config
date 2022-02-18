// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

interface IEvmHooks {

    function registerDeployedContract(address account, address impl) external;

    function checkContractActive(address impl) external;
}