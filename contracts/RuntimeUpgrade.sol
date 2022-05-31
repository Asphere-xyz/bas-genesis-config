// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/utils/Create2.sol";

import "./Injector.sol";
import "./Staking.sol";
import "./SlashingIndicator.sol";
import "./SystemReward.sol";
import "./StakingPool.sol";
import "./Governance.sol";
import "./ChainConfig.sol";
import "./DeployerProxy.sol";

contract RuntimeProxy is ERC1967Proxy {

    constructor(address runtimeUpgrade, bytes memory bytecode, bytes memory inputData) ERC1967Proxy(_deployDefaultVersion(bytecode), inputData) {
        _changeAdmin(runtimeUpgrade);
    }

    function getCurrentVersion() public view returns (address) {
        return _implementation();
    }

    function _deployDefaultVersion(bytes memory bytecode) internal returns (address) {
        return Create2.deploy(0, bytes32(0x00), bytecode);
    }

    modifier onlyFromRuntimeUpgrade() {
        require(msg.sender == _getAdmin(), "ManageableProxy: only runtime upgrade");
        _;
    }

    function upgradeToAndCall(address impl, bytes memory data) external onlyFromRuntimeUpgrade {
        _upgradeToAndCall(impl, data, false);
    }
}

contract RuntimeUpgrade is InjectorContextHolder, IRuntimeUpgrade {

    event Upgraded(address contractAddress, bytes newByteCode);
    event Deployed(address contractAddress, bytes newByteCode);

    struct GenesisConfig {
        // staking
        address[] validators;
        uint256[] initialStakes;
        uint16 commissionRate;
        // chain config
        uint32 activeValidatorsLength;
        uint32 epochBlockInterval;
        uint32 misdemeanorThreshold;
        uint32 felonyThreshold;
        uint32 validatorJailEpochLength;
        uint32 undelegatePeriod;
        uint256 minValidatorStakeAmount;
        uint256 minStakingAmount;
        // system reward
        address[] treasuryAccounts;
        uint16[] treasuryShares;
        // governance
        uint64 votingPeriod;
        string governanceName;
        // deployer proxy
        address[] deployers;
    }

    // address of the EVM hook (not in use anymore)
    address internal _evmHookAddress;
    // list of new deployed system smart contracts
    address[] internal _deployedSystemContracts;
    // genesis config
    GenesisConfig internal _genesisConfig;

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

    function initialize(GenesisConfig memory genesisConfig) external initializer {
        _genesisConfig = genesisConfig;
    }

    function init() external onlyBlockOne override {
        // initialize system contracts (chain config must be the first)
        ChainConfig(payable(address(_CHAIN_CONFIG_CONTRACT))).initialize(
            _genesisConfig.activeValidatorsLength,
            _genesisConfig.epochBlockInterval,
            _genesisConfig.misdemeanorThreshold,
            _genesisConfig.felonyThreshold,
            _genesisConfig.validatorJailEpochLength,
            _genesisConfig.undelegatePeriod,
            _genesisConfig.minValidatorStakeAmount,
            _genesisConfig.minStakingAmount
        );
        Staking(payable(address(_STAKING_CONTRACT))).initialize(_genesisConfig.validators, _genesisConfig.initialStakes, _genesisConfig.commissionRate);
        SlashingIndicator(payable(address(_SLASHING_INDICATOR_CONTRACT))).initialize();
        SystemReward(payable(address(_SYSTEM_REWARD_CONTRACT))).initialize(_genesisConfig.treasuryAccounts, _genesisConfig.treasuryShares);
        Governance(payable(address(_GOVERNANCE_CONTRACT))).initialize(_genesisConfig.votingPeriod, _genesisConfig.governanceName);
        DeployerProxy(payable(address(_DEPLOYER_PROXY_CONTRACT))).initialize(_genesisConfig.deployers);
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
        require(proxy.getCurrentVersion() != address(0x00), "RuntimeUpgrade: implementation not found");
        // we allow to upgrade only system smart contracts
        require(_isSystemSmartContract(account), "RuntimeUpgrade: only system smart contract");
        // upgrade system contract
        address impl = Create2.deploy(0, salt, bytecode);
        proxy.upgradeToAndCall(impl, data);
    }

    function deploySystemSmartContract(address payable account, bytes calldata bytecode, bytes32 salt, bytes calldata data) external onlyFromGovernance virtual override {
        // make sure that we're upgrading existing smart contract that already has implementation
        RuntimeProxy proxy = RuntimeProxy(account);
        require(proxy.getCurrentVersion() == address(0x00), "RuntimeUpgrade: already deployed");
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