// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "./interfaces/IChainConfig.sol";
import "./interfaces/IGovernance.sol";
import "./interfaces/ISlashingIndicator.sol";
import "./interfaces/ISystemReward.sol";
import "./interfaces/IRuntimeUpgradeEvmHook.sol";
import "./interfaces/IValidatorSet.sol";
import "./interfaces/IStaking.sol";
import "./interfaces/IRuntimeUpgrade.sol";
import "./interfaces/IStakingPool.sol";
import "./interfaces/IInjector.sol";
import "./interfaces/IDeployerProxy.sol";

abstract contract AlreadyInit {

    // flag indicating is smart contract initialized already
    bool internal _init;

    modifier whenNotInitialized() {
        require(!_init, "Injector: already initialized");
        _;
        _init = true;
    }

    modifier whenInitialized() {
        require(_init, "Injector: not initialized yet");
        _;
    }
}

abstract contract InjectorContextHolder is AlreadyInit, IInjector {

    // system smart contract constructor
    bytes internal _ctor;

    // BSC compatible contracts
    IStaking internal _stakingContract;
    ISlashingIndicator internal _slashingIndicatorContract;
    ISystemReward internal _systemRewardContract;
    // BAS defined contracts
    IStakingPool internal _stakingPoolContract;
    IGovernance internal _governanceContract;
    IChainConfig internal _chainConfigContract;
    IRuntimeUpgrade internal _runtimeUpgradeContract;
    IDeployerProxy internal _deployerProxyContract;

    // already init (1) + injector (7) = 8
    uint256[100 - 8] private __reserved;

    constructor(bytes memory constructorParams) {
        // save constructor params to use them in the init function
        _ctor = constructorParams;
    }

    function init() external whenNotInitialized {
        // BSC compatible addresses
        _stakingContract = IStaking(0x0000000000000000000000000000000000001000);
        _slashingIndicatorContract = ISlashingIndicator(0x0000000000000000000000000000000000001001);
        _systemRewardContract = ISystemReward(0x0000000000000000000000000000000000001002);
        // BAS defined addresses
        _stakingPoolContract = IStakingPool(0x0000000000000000000000000000000000007001);
        _governanceContract = IGovernance(0x0000000000000000000000000000000000007002);
        _chainConfigContract = IChainConfig(0x0000000000000000000000000000000000007003);
        _runtimeUpgradeContract = IRuntimeUpgrade(0x0000000000000000000000000000000000007004);
        _deployerProxyContract = IDeployerProxy(0x0000000000000000000000000000000000007005);
        // invoke constructor
        _invokeContractConstructor();
    }

    function initManually(
        IStaking stakingContract,
        ISlashingIndicator slashingIndicatorContract,
        ISystemReward systemRewardContract,
        IStakingPool stakingPoolContract,
        IGovernance governanceContract,
        IChainConfig chainConfigContract,
        IRuntimeUpgrade runtimeUpgradeContract,
        IDeployerProxy deployerProxyContract
    ) public whenNotInitialized {
        // BSC-compatible
        _stakingContract = stakingContract;
        _slashingIndicatorContract = slashingIndicatorContract;
        _systemRewardContract = systemRewardContract;
        // BAS-defined
        _stakingPoolContract = stakingPoolContract;
        _governanceContract = governanceContract;
        _chainConfigContract = chainConfigContract;
        _runtimeUpgradeContract = runtimeUpgradeContract;
        _deployerProxyContract = deployerProxyContract;
        // invoke constructor
        _invokeContractConstructor();
    }

    function getSystemContracts() public view override returns (address[] memory) {
        address[] memory result = new address[](8);
        // BSC-compatible
        result[0] = address(_stakingContract);
        result[1] = address(_slashingIndicatorContract);
        result[2] = address(_systemRewardContract);
        // BAS-defined
        result[3] = address(_stakingPoolContract);
        result[4] = address(_governanceContract);
        result[5] = address(_chainConfigContract);
        result[6] = address(_runtimeUpgradeContract);
        result[7] = address(_deployerProxyContract);
        return result;
    }

    function _isSystemSmartContract(address contractAddress) internal returns (bool) {
        address[] memory systemContracts = getSystemContracts();
        for (uint256 i = 0; i < systemContracts.length; i++) {
            if (systemContracts[i] == contractAddress) return true;
        }
        return false;
    }

    function _invokeContractConstructor() internal {
        if (_ctor.length == 0) {
            return;
        }
        (bool success, bytes memory returnData) = address(this).call(_ctor);
        // if everything is success then just exit w/o revert
        if (success) {
            return;
        }
        if (returnData.length == 0) {
            revert("Injector: construction failed w/ unknown error");
        }
        assembly {
            let returnDataSize := mload(returnData)
            revert(add(32, returnData), returnDataSize)
        }
    }

    function isInitialized() external view returns (bool) {
        return _init;
    }

    modifier onlyFromCoinbase() {
        require(msg.sender == block.coinbase, "InjectorContextHolder: only coinbase");
        _;
    }

    modifier onlyFromSlashingIndicator() {
        require(msg.sender == address(_slashingIndicatorContract), "InjectorContextHolder: only slashing indicator");
        _;
    }

    modifier onlyFromGovernance() {
        require(IGovernance(msg.sender) == _governanceContract, "InjectorContextHolder: only governance");
        _;
    }

    modifier onlyFromRuntimeUpgrade() {
        require(IRuntimeUpgrade(msg.sender) == _runtimeUpgradeContract, "InjectorContextHolder: only runtime upgrade");
        _;
    }

    modifier onlyZeroGasPrice() {
        require(tx.gasprice == 0, "InjectorContextHolder: only zero gas price");
        _;
    }

    function getStaking() public view returns (IStaking) {
        return _stakingContract;
    }

    function getSlashingIndicator() public view returns (ISlashingIndicator) {
        return _slashingIndicatorContract;
    }

    function getSystemReward() public view returns (ISystemReward) {
        return _systemRewardContract;
    }

    function getStakingPool() public view returns (IStakingPool) {
        return _stakingPoolContract;
    }

    function getGovernance() public view returns (IGovernance) {
        return _governanceContract;
    }

    function getChainConfig() public view returns (IChainConfig) {
        return _chainConfigContract;
    }
}
