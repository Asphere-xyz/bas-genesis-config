// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "./InjectorContextHolder.sol";

contract DeployerProxy is InjectorContextHolder, IDeployerProxy {

    event DeployerAdded(address indexed account);
    event DeployerRemoved(address indexed account);
    event DeployerBanned(address indexed account);
    event DeployerUnbanned(address indexed account);
    event ContractDisabled(address indexed contractAddress);
    event ContractEnabled(address indexed contractAddress);

    event ContractDeployed(address indexed account, address impl);

    struct Deployer {
        bool exists;
        address account;
        bool banned;
    }

    enum ContractState {
        NotFound,
        Enabled,
        Disabled
    }

    struct SmartContract {
        ContractState state;
        address impl;
        address deployer;
    }

    mapping(address => Deployer) private _contractDeployers;
    mapping(address => SmartContract) private _smartContracts;

    constructor(
        IStaking stakingContract,
        ISlashingIndicator slashingIndicatorContract,
        ISystemReward systemRewardContract,
        IStakingPool stakingPoolContract,
        IGovernance governanceContract,
        IChainConfig chainConfigContract,
        IRuntimeUpgrade runtimeUpgradeContract,
        IDeployerProxy deployerProxyContract
    ) InjectorContextHolder(
        stakingContract,
        slashingIndicatorContract,
        systemRewardContract,
        stakingPoolContract,
        governanceContract,
        chainConfigContract,
        runtimeUpgradeContract,
        deployerProxyContract
    ) {
    }

    function initialize(address[] memory deployers) external initializer {
        for (uint256 i = 0; i < deployers.length; i++) {
            _addDeployer(deployers[i]);
        }
    }

    function isDeployer(address account) public override view returns (bool) {
        return _contractDeployers[account].exists;
    }

    function isBanned(address account) public override view returns (bool) {
        return _contractDeployers[account].banned;
    }

    function addDeployer(address account) public onlyFromGovernance virtual override {
        _addDeployer(account);
    }

    function _addDeployer(address account) internal {
        require(!_contractDeployers[account].exists, "deployer already exist");
        _contractDeployers[account] = Deployer({
        exists : true,
        account : account,
        banned : false
        });
        emit DeployerAdded(account);
    }

    function removeDeployer(address account) public onlyFromGovernance virtual override {
        _removeDeployer(account);
    }

    function _removeDeployer(address account) internal {
        require(_contractDeployers[account].exists, "deployer doesn't exist");
        delete _contractDeployers[account];
        emit DeployerRemoved(account);
    }

    function banDeployer(address account) public onlyFromGovernance virtual override {
        _banDeployer(account);
    }

    function _banDeployer(address account) internal {
        require(_contractDeployers[account].exists, "deployer doesn't exist");
        require(!_contractDeployers[account].banned, "deployer already banned");
        _contractDeployers[account].banned = true;
        emit DeployerBanned(account);
    }

    function _unbanDeployer(address account) internal {
        require(_contractDeployers[account].exists, "deployer doesn't exist");
        require(_contractDeployers[account].banned, "deployer is not banned");
        _contractDeployers[account].banned = false;
        emit DeployerUnbanned(account);
    }

    function unbanDeployer(address account) public onlyFromGovernance virtual override {
        _unbanDeployer(account);
    }

    function getContractState(address contractAddress) external view virtual override returns (uint8 state, address impl, address deployer) {
        SmartContract memory dc = _smartContracts[contractAddress];
        state = uint8(dc.state);
        impl = dc.impl;
        deployer = dc.deployer;
    }

    function _registerDeployedContract(address deployer, address impl) internal {
        // make sure this call is allowed
        require(isDeployer(deployer), "deployer is not allowed");
        // remember who deployed contract
        SmartContract memory dc = _smartContracts[impl];
        require(dc.impl == address(0x00), "contract is deployed already");
        dc.state = ContractState.Enabled;
        dc.impl = impl;
        dc.deployer = deployer;
        _smartContracts[impl] = dc;
        // emit event
        emit ContractDeployed(deployer, impl);
    }

    function registerDeployedContract(address deployer, address impl) public onlyFromCoinbase virtual override {
        _registerDeployedContract(deployer, impl);
    }

    function checkContractActive(address impl) external view virtual override {
        _checkContractActive(impl);
    }

    function _checkContractActive(address impl) internal view {
        // check that contract is not disabled
        SmartContract memory dc = _smartContracts[impl];
        require(dc.state != ContractState.Disabled, "contract is not enabled");
    }

    function disableContract(address impl) public onlyFromGovernance virtual override {
        _disableContract(impl);
    }

    function enableContract(address impl) public onlyFromGovernance virtual override {
        _enableContract(impl);
    }

    function _disableContract(address contractAddress) internal {
        SmartContract memory dc = _smartContracts[contractAddress];
        require(dc.state == ContractState.Enabled, "contract already disabled");
        dc.state = ContractState.Disabled;
        _smartContracts[contractAddress] = dc;
        //emit event
        emit ContractDisabled(contractAddress);
    }

    function _enableContract(address contractAddress) internal {
        SmartContract memory dc = _smartContracts[contractAddress];
        require(dc.state == ContractState.Disabled, "contract already enabled");
        dc.state = ContractState.Enabled;
        _smartContracts[contractAddress] = dc;
        //emit event
        emit ContractEnabled(contractAddress);
    }
}