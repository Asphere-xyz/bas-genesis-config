// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "./Injector.sol";

contract RuntimeUpgrade is InjectorContextHolder, IRuntimeUpgrade {

    event SmartContractUpgrade(address contractAddress, bytes newByteCode);

    // address of the EVM hook
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

    function initialize(address evmHookAddress) external initializer {
        _evmHookAddress = evmHookAddress;
    }

    function getEvmHookAddress() external view override returns (address) {
        return _evmHookAddress;
    }

    function upgradeSystemSmartContract(
        address systemContractAddress,
        bytes calldata newByteCode,
        bytes calldata applyFunction
    ) external onlyFromGovernance virtual override {
        // we allow to upgrade only system smart contracts
        require(_isSystemSmartContract(systemContractAddress), "RuntimeUpgrade: only system smart contract");
        // upgrade system contract
        _upgradeSystemSmartContract(systemContractAddress, newByteCode, applyFunction, IRuntimeUpgradeEvmHook.upgradeTo.selector);
    }

    function deploySystemSmartContract(
        address systemContractAddress,
        bytes calldata newByteCode,
        bytes calldata applyFunction
    ) external onlyFromGovernance virtual override {
        // disallow to upgrade plain contracts or system contracts (only new)
        require(!_isContract(systemContractAddress) && !_isSystemSmartContract(systemContractAddress), "RuntimeUpgrade: only new address");
        require(systemContractAddress != address(_RUNTIME_UPGRADE_CONTRACT), "RuntimeUpgrade: this contract can't be upgraded");
        // upgrade system contract with provided bytecode
        _upgradeSystemSmartContract(systemContractAddress, newByteCode, applyFunction, IRuntimeUpgradeEvmHook.deployTo.selector);
        // extend list of new system contracts to let it be a system smart contract
        _deployedSystemContracts.push(systemContractAddress);
    }

    function getSystemContracts() public view override returns (address[] memory) {
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

    function _isContract(address account) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }

    function _isSystemSmartContract(address contractAddress) internal view returns (bool) {
        address[] memory systemContracts = getSystemContracts();
        for (uint256 i = 0; i < systemContracts.length; i++) {
            if (systemContracts[i] == contractAddress) return true;
        }
        return false;
    }

    function _upgradeSystemSmartContract(
        address systemContractAddress,
        bytes calldata newByteCode,
        bytes calldata applyFunction,
        bytes4 deploySelector
    ) internal {
        // modify bytecode using EVM hook
        bytes memory inputData = abi.encodeWithSelector(deploySelector, systemContractAddress, newByteCode);
        (bool result,) = address(_evmHookAddress).call(inputData);
        require(result, "RuntimeUpgrade: failed to invoke EVM hook");
        // if this is new smart contract then run "init" function
//        IInjector injector = IInjector(systemContractAddress);
//        if (!injector.isInitialized()) {
//            injector.init();
//        }
        // call migration function if specified
        if (applyFunction.length > 0) {
            (bool result2,) = systemContractAddress.call(applyFunction);
            require(result2, "RuntimeUpgrade: migration failed");
        }
        // emit event
        emit SmartContractUpgrade(systemContractAddress, newByteCode);
    }
}