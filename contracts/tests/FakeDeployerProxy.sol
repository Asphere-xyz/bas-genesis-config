// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "../DeployerProxy.sol";

contract FakeDeployerProxy is DeployerProxy {

    constructor(bytes memory ctor) DeployerProxy(ctor) {
    }

    function addDeployer(address account) public override {
        _addDeployer(account);
    }

    function removeDeployer(address account) public override {
        _removeDeployer(account);
    }

    function banDeployer(address account) public override {
        _banDeployer(account);
    }

    function unbanDeployer(address account) public override {
        _unbanDeployer(account);
    }

    function registerDeployedContract(address deployer, address impl) public override {
        _registerDeployedContract(deployer, impl);
    }

    function checkContractActive(address impl) external view override {
        _checkContractActive(impl);
    }

    function disableContract(address impl) public override {
        _disableContract(impl);
    }

    function enableContract(address impl) public override {
        _enableContract(impl);
    }
}