// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/utils/StorageSlot.sol";

import "./common/RetryMixin.sol";
import "./common/RetryableProxy.sol";
import "./common/Multicall.sol";

import "./staking/interfaces/IStakingConfig.sol";
import "./staking/interfaces/IStaking.sol";
import "./staking/interfaces/IStakingPool.sol";
import "./runtime/interfaces/IRuntimeUpgrade.sol";
import "./acl/interfaces/IDeployerProxy.sol";
import "./parlia/interfaces/IGovernance.sol";
import "./parlia/interfaces/ISlashingIndicator.sol";
import "./parlia/interfaces/ISystemReward.sol";
import "./relay/interfaces/IRelayHub.sol";
import "./relay/interfaces/ICrossChainBridge.sol";

abstract contract InjectorContextHolder is Initializable, Multicall {

    // default layout offset, it means that all inherited smart contract's storage layout must start from 100
    uint256 internal constant _LAYOUT_OFFSET = 100;
    uint256 internal constant _SKIP_OFFSET = 10;

    // BSC compatible smart contracts
    IStaking internal immutable _STAKING_CONTRACT;
    ISlashingIndicator internal immutable _SLASHING_INDICATOR_CONTRACT;
    ISystemReward internal immutable _SYSTEM_REWARD_CONTRACT;
    IStakingPool internal immutable _STAKING_POOL_CONTRACT;
    IGovernance internal immutable _GOVERNANCE_CONTRACT;
    IStakingConfig internal immutable _STAKING_CONFIG_CONTRACT;
    IRuntimeUpgrade internal immutable _RUNTIME_UPGRADE_CONTRACT;
    IDeployerProxy internal immutable _DEPLOYER_PROXY_CONTRACT;
    IRelayHub internal immutable _RELAY_HUB_CONTRACT;
    ICrossChainBridge internal immutable _CROSS_CHAIN_BRIDGE_CONTRACT;

    // delayed initializer input data (only for parlia mode)
    bytes internal _delayedInitializer;

    // already used fields
    uint256[_SKIP_OFFSET] private __removed;
    // reserved (2 for init and initializer)
    uint256[_LAYOUT_OFFSET - _SKIP_OFFSET - 2] private __reserved;

    struct ConstructorArguments {
        IStaking stakingContract;
        ISlashingIndicator slashingIndicatorContract;
        ISystemReward systemRewardContract;
        IStakingPool stakingPoolContract;
        IGovernance governanceContract;
        IStakingConfig chainConfigContract;
        IRuntimeUpgrade runtimeUpgradeContract;
        IDeployerProxy deployerProxyContract;
        IRelayHub relayHubContract;
        ICrossChainBridge crossChainBridgeContract;
    }

    error OnlyCoinbase(address coinbase);
    error OnlySlashingIndicator();
    error OnlyGovernance();
    error OnlyBlock(uint64 blockNumber);

    constructor(ConstructorArguments memory constructorArgs) {
        _STAKING_CONTRACT = constructorArgs.stakingContract;
        _SLASHING_INDICATOR_CONTRACT = constructorArgs.slashingIndicatorContract;
        _SYSTEM_REWARD_CONTRACT = constructorArgs.systemRewardContract;
        _STAKING_POOL_CONTRACT = constructorArgs.stakingPoolContract;
        _GOVERNANCE_CONTRACT = constructorArgs.governanceContract;
        _STAKING_CONFIG_CONTRACT = constructorArgs.chainConfigContract;
        _RUNTIME_UPGRADE_CONTRACT = constructorArgs.runtimeUpgradeContract;
        _DEPLOYER_PROXY_CONTRACT = constructorArgs.deployerProxyContract;
        _RELAY_HUB_CONTRACT = constructorArgs.relayHubContract;
        _CROSS_CHAIN_BRIDGE_CONTRACT = constructorArgs.crossChainBridgeContract;
    }

    function useDelayedInitializer(bytes memory delayedInitializer) external onlyBlock(0) {
        _delayedInitializer = delayedInitializer;
    }

    function init() external onlyBlock(1) virtual {
        if (_delayedInitializer.length > 0) {
            _delegateCall(_delayedInitializer);
        }
    }

    function isInitialized() public view returns (bool) {
        // openzeppelin's class "Initializable" doesnt expose any methods for fetching initialisation status
        StorageSlot.Uint256Slot storage initializedSlot = StorageSlot.getUint256Slot(bytes32(0x0000000000000000000000000000000000000000000000000000000000000000));
        return initializedSlot.value > 0;
    }

    modifier onlyFromCoinbase() virtual {
        if (msg.sender != block.coinbase) revert OnlyCoinbase(block.coinbase);
        _;
    }

    modifier onlyFromSlashingIndicator() virtual {
        if (ISlashingIndicator(msg.sender) != _SLASHING_INDICATOR_CONTRACT) revert OnlySlashingIndicator();
        _;
    }

    modifier onlyFromGovernance() virtual {
        if (IGovernance(msg.sender) != _GOVERNANCE_CONTRACT) revert OnlyGovernance();
        _;
    }

    modifier onlyBlock(uint64 blockNumber) virtual {
        if (block.number != blockNumber) revert OnlyBlock(blockNumber);
        _;
    }
}
