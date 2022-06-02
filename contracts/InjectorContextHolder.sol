// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/utils/StorageSlot.sol";

import "./interfaces/IChainConfig.sol";
import "./interfaces/IGovernance.sol";
import "./interfaces/ISlashingIndicator.sol";
import "./interfaces/ISystemReward.sol";
import "./interfaces/IValidatorSet.sol";
import "./interfaces/IStaking.sol";
import "./interfaces/IRuntimeUpgrade.sol";
import "./interfaces/IStakingPool.sol";
import "./interfaces/IInjectorContextHolder.sol";
import "./interfaces/IDeployerProxy.sol";

abstract contract InjectorContextHolder is Initializable, IInjectorContextHolder {

    // default layout offset, it means that all inherited smart contract's storage layout must start from 100
    uint256 internal constant _LAYOUT_OFFSET = 100;
    uint256 internal constant _SKIP_OFFSET = 10;

    // BSC compatible smart contracts
    IStaking internal immutable _STAKING_CONTRACT;
    ISlashingIndicator internal immutable _SLASHING_INDICATOR_CONTRACT;
    ISystemReward internal immutable _SYSTEM_REWARD_CONTRACT;
    IStakingPool internal immutable _STAKING_POOL_CONTRACT;
    IGovernance internal immutable _GOVERNANCE_CONTRACT;
    IChainConfig internal immutable _CHAIN_CONFIG_CONTRACT;
    IRuntimeUpgrade internal immutable _RUNTIME_UPGRADE_CONTRACT;
    IDeployerProxy internal immutable _DEPLOYER_PROXY_CONTRACT;

    // delayed initializer input data (only for parlia mode)
    bytes internal _delayedInitializer;

    // already used fields
    uint256[_SKIP_OFFSET] private __removed;
    // reserved (2 for init and initializer)
    uint256[_LAYOUT_OFFSET - _SKIP_OFFSET - 2] private __reserved;

    error OnlyCoinbase(address coinbase);
    error OnlySlashingIndicator();
    error OnlyGovernance();
    error OnlyRuntimeUpgrade();
    error OnlyZeroGasPrice();
    error OnlyBlock(uint64 blockNumber);
    error OnlyGenesisBlock();
    error OnlyBlockOne();

    constructor(
        IStaking stakingContract,
        ISlashingIndicator slashingIndicatorContract,
        ISystemReward systemRewardContract,
        IStakingPool stakingPoolContract,
        IGovernance governanceContract,
        IChainConfig chainConfigContract,
        IRuntimeUpgrade runtimeUpgradeContract,
        IDeployerProxy deployerProxyContract
    ) {
        _STAKING_CONTRACT = stakingContract;
        _SLASHING_INDICATOR_CONTRACT = slashingIndicatorContract;
        _SYSTEM_REWARD_CONTRACT = systemRewardContract;
        _STAKING_POOL_CONTRACT = stakingPoolContract;
        _GOVERNANCE_CONTRACT = governanceContract;
        _CHAIN_CONFIG_CONTRACT = chainConfigContract;
        _RUNTIME_UPGRADE_CONTRACT = runtimeUpgradeContract;
        _DEPLOYER_PROXY_CONTRACT = deployerProxyContract;
    }

    function useDelayedInitializer(bytes memory delayedInitializer) external onlyBlock(0) {
        _delayedInitializer = delayedInitializer;
    }

    function init() external onlyBlock(1) virtual {
        if (_delayedInitializer.length > 0) {
            (bool success, bytes memory returnData) = address(this).delegatecall(_delayedInitializer);
            if (success) return;
            if (returnData.length > 0) {
                assembly {
                    revert(add(32, returnData), mload(returnData))
                }
            } else {
                revert("call of init() failed");
            }
        }
    }

    function isInitialized() public view override returns (bool) {
        // openzeppelin's class "Initializable" doesnt expose any methods for fetching initialisation status
        StorageSlot.Uint256Slot storage initializedSlot = StorageSlot.getUint256Slot(bytes32(0x0000000000000000000000000000000000000000000000000000000000000001));
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

    modifier onlyFromRuntimeUpgrade() virtual {
        if (IRuntimeUpgrade(msg.sender) != _RUNTIME_UPGRADE_CONTRACT) revert OnlyRuntimeUpgrade();
        _;
    }

    modifier onlyZeroGasPrice() virtual {
        if (tx.gasprice != 0) revert OnlyZeroGasPrice();
        _;
    }

    modifier onlyBlock(uint64 blockNumber) virtual {
        if (block.number != blockNumber) revert OnlyBlock(blockNumber);
        _;
    }

    function getStaking() public view returns (IStaking) {
        return _STAKING_CONTRACT;
    }

    function getSlashingIndicator() public view returns (ISlashingIndicator) {
        return _SLASHING_INDICATOR_CONTRACT;
    }

    function getSystemReward() public view returns (ISystemReward) {
        return _SYSTEM_REWARD_CONTRACT;
    }

    function getStakingPool() public view returns (IStakingPool) {
        return _STAKING_POOL_CONTRACT;
    }

    function getGovernance() public view returns (IGovernance) {
        return _GOVERNANCE_CONTRACT;
    }

    function getChainConfig() public view returns (IChainConfig) {
        return _CHAIN_CONFIG_CONTRACT;
    }
}
