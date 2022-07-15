// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

interface IDeployerProxy {

    function registerDeployedContract(address account, address impl) external;

    function checkContractActive(address impl) external;

    function isDeployer(address account) external view returns (bool);

    function getContractState(address contractAddress) external view returns (uint8 state, address impl, address deployer);

    function isBanned(address account) external view returns (bool);

    function addDeployer(address account) external;

    function banDeployer(address account) external;

    function unbanDeployer(address account) external;

    function removeDeployer(address account) external;

    function disableContract(address contractAddress) external;

    function enableContract(address contractAddress) external;
}