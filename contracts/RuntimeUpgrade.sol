// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/utils/Create2.sol";

import "./InjectorContextHolder.sol";
import "./RuntimeProxy.sol";

contract RuntimeUpgrade is InjectorContextHolder, IRuntimeUpgrade {

    bytes32 constant internal _DEPLOYMENT_SALT = 0x0000000000000000000000000000000000000000000000000000000000000000;

    event Upgraded(address account, address impl, bytes bytecode);
    event Deployed(address account, address impl, bytes bytecode);

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

    function isEIP1967() external pure returns (bool) {
        return true;
    }

    function upgradeSystemSmartContract(address payable account, bytes calldata bytecode, bytes calldata data) external payable onlyFromGovernance virtual override {
        // make sure that we're upgrading existing smart contract that already has implementation
        RuntimeProxy proxy = RuntimeProxy(account);
        require(proxy.implementation() != address(0x00), "RuntimeUpgrade: implementation not found");
        // we allow to upgrade only system smart contracts
        require(_isSystemSmartContract(account), "RuntimeUpgrade: only system smart contract");
        // upgrade system contract
        address impl = Create2.deploy(msg.value, _DEPLOYMENT_SALT, bytecode);
        if (data.length > 0) {
            proxy.upgradeToAndCall(impl, data);
        } else {
            proxy.upgradeTo(impl);
        }
        // emit event
        emit Upgraded(account, impl, bytecode);
    }

    function deploySystemSmartContract(address payable account, bytes calldata bytecode, bytes calldata data) external payable onlyFromGovernance virtual override {
        // make sure that we're upgrading existing smart contract that already has implementation
        RuntimeProxy proxy = RuntimeProxy(account);
        require(proxy.implementation() == address(0x00), "RuntimeUpgrade: already deployed");
        // we allow to upgrade only system smart contracts
        require(!_isSystemSmartContract(account), "RuntimeUpgrade: already deployed");
        _deployedSystemContracts.push(account);
        // upgrade system contract
        address impl = Create2.deploy(msg.value, _DEPLOYMENT_SALT, bytecode);
        if (data.length > 0) {
            proxy.upgradeToAndCall(impl, data);
        } else {
            proxy.upgradeTo(impl);
        }
        // emit event
        emit Deployed(account, impl, bytecode);
    }

    function getSystemContracts() public view returns (address[] memory) {
        address[] memory result = new address[](8 + _deployedSystemContracts.length);
        // BSC-compatible
        result[0] = address(_STAKING_CONTRACT);
        result[1] = address(_SLASHING_INDICATOR_CONTRACT);
        result[2] = address(_SYSTEM_REWARD_CONTRACT);
        // BAS-defined
        result[3] = address(_STAKING_POOL_CONTRACT);
        result[4] = address(_GOVERNANCE_CONTRACT);
        result[5] = address(_CHAIN_CONFIG_CONTRACT);
        result[6] = address(_RUNTIME_UPGRADE_CONTRACT);
        result[7] = address(_DEPLOYER_PROXY_CONTRACT);
        // copy deployed system smart contracts
        for (uint256 i = 0; i < _deployedSystemContracts.length; i++) {
            result[8 + i] = _deployedSystemContracts[i];
        }
        return result;
    }

    function _isSystemSmartContract(address contractAddress) internal view returns (bool) {
        address[] memory systemContracts = getSystemContracts();
        for (uint256 i = 0; i < systemContracts.length; i++) {
            if (systemContracts[i] == contractAddress) return true;
        }
        return false;
    }
}