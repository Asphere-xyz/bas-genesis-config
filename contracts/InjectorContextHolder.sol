// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "./interfaces/IChainConfig.sol";
import "./interfaces/IGovernance.sol";
import "./interfaces/ISlashingIndicator.sol";
import "./interfaces/ISystemReward.sol";
import "./interfaces/IValidatorSet.sol";
import "./interfaces/IStaking.sol";
import "./interfaces/IRuntimeUpgrade.sol";
import "./interfaces/IStakingPool.sol";
import "./interfaces/IInjector.sol";
import "./interfaces/IDeployerProxy.sol";

abstract contract InjectorContextHolder is Initializable, IInjector {

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

    // already used fields
    uint256[_SKIP_OFFSET] private __removed;
    // reserved (1 for init)
    uint256[_LAYOUT_OFFSET - _SKIP_OFFSET - 1] private __reserved;

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

    function init() external onlyBlockOne virtual {
        // if you use proxy setup then this function call is handled by proxy
    }

    modifier onlyFromCoinbase() virtual {
        require(msg.sender == block.coinbase, "InjectorContextHolder: only coinbase");
        _;
    }

    modifier onlyFromSlashingIndicator() virtual {
        require(msg.sender == address(_SLASHING_INDICATOR_CONTRACT), "InjectorContextHolder: only slashing indicator");
        _;
    }

    modifier onlyFromGovernance() virtual {
        require(IGovernance(msg.sender) == _GOVERNANCE_CONTRACT, "InjectorContextHolder: only governance");
        _;
    }

    modifier onlyFromRuntimeUpgrade() virtual {
        require(IRuntimeUpgrade(msg.sender) == _RUNTIME_UPGRADE_CONTRACT, "InjectorContextHolder: only runtime upgrade");
        _;
    }

    modifier onlyZeroGasPrice() virtual {
        require(tx.gasprice == 0, "InjectorContextHolder: only zero gas price");
        _;
    }

    modifier onlyBlockOne() virtual {
        require(block.number == 1, "InjectorContextHolder: only block one");
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
