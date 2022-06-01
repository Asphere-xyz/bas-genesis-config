// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/utils/Create2.sol";

import "./InjectorContextHolder.sol";
import "./RuntimeProxy.sol";

contract RuntimeUpgrade is InjectorContextHolder, IRuntimeUpgrade {

    event Upgraded(address contractAddress, bytes newByteCode);
    event Deployed(address contractAddress, bytes newByteCode);

    // address of the EVM hook (not in use anymore)
    address internal _evmHookAddress;
    // list of new deployed system smart contracts
    address[] internal _deployedSystemContracts;

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

    function init() external onlyBlock(1) override {
        // fill array with deployed smart contracts
        _deployedSystemContracts.push(address(_STAKING_CONTRACT));
        _deployedSystemContracts.push(address(_SLASHING_INDICATOR_CONTRACT));
        _deployedSystemContracts.push(address(_SYSTEM_REWARD_CONTRACT));
        _deployedSystemContracts.push(address(_STAKING_POOL_CONTRACT));
        _deployedSystemContracts.push(address(_GOVERNANCE_CONTRACT));
        _deployedSystemContracts.push(address(_CHAIN_CONFIG_CONTRACT));
        _deployedSystemContracts.push(address(_RUNTIME_UPGRADE_CONTRACT));
        _deployedSystemContracts.push(address(_DEPLOYER_PROXY_CONTRACT));
    }

    function upgradeSystemSmartContract(address payable account, bytes calldata bytecode, bytes32 salt, bytes calldata data) external onlyFromGovernance virtual override {
        // make sure that we're upgrading existing smart contract that already has implementation
        RuntimeProxy proxy = RuntimeProxy(account);
        require(proxy.implementation() != address(0x00), "RuntimeUpgrade: implementation not found");
        // we allow to upgrade only system smart contracts
        require(_isSystemSmartContract(account), "RuntimeUpgrade: only system smart contract");
        // upgrade system contract
        address impl = Create2.deploy(0, salt, bytecode);
        proxy.upgradeToAndCall(impl, data);
    }

    function deploySystemSmartContract(address payable account, bytes calldata bytecode, bytes32 salt, bytes calldata data) external onlyFromGovernance virtual override {
        // make sure that we're upgrading existing smart contract that already has implementation
        RuntimeProxy proxy = RuntimeProxy(account);
        require(proxy.implementation() == address(0x00), "RuntimeUpgrade: already deployed");
        // we allow to upgrade only system smart contracts
        require(!_isSystemSmartContract(account), "RuntimeUpgrade: already deployed");
        // upgrade system contract
        address impl = Create2.deploy(0, salt, bytecode);
        proxy.upgradeToAndCall(impl, data);
    }

    function getSystemContracts() public view returns (address[] memory) {
        return _deployedSystemContracts;
    }

    function _isSystemSmartContract(address contractAddress) internal view returns (bool) {
        address[] memory systemContracts = getSystemContracts();
        for (uint256 i = 0; i < systemContracts.length; i++) {
            if (systemContracts[i] == contractAddress) return true;
        }
        return false;
    }
}