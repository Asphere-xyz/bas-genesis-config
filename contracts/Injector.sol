// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "./interfaces/IChainConfig.sol";
import "./interfaces/IEvmHooks.sol";
import "./interfaces/IGovernance.sol";
import "./interfaces/ISlashingIndicator.sol";
import "./interfaces/ISystemReward.sol";
import "./interfaces/IValidatorSet.sol";
import "./interfaces/IStaking.sol";
import "./interfaces/IStakingPool.sol";
import "./interfaces/IInjector.sol";

abstract contract InjectorContextHolder is IInjector {

    bool private _init;
    uint256 private _operatingBlock;

    // BSC compatible contracts
    IStaking internal _stakingContract;
    ISlashingIndicator internal _slashingIndicatorContract;
    ISystemReward internal _systemRewardContract;
    // BAS defined contracts
    IStakingPool internal _stakingPoolContract;
    IGovernance internal _governanceContract;
    IChainConfig internal _chainConfigContract;

    uint256[100 - 8] private __reserved;

    function init() public whenNotInitialized virtual {
        // BSC compatible addresses
        _stakingContract = IStaking(0x0000000000000000000000000000000000001000);
        _slashingIndicatorContract = ISlashingIndicator(0x0000000000000000000000000000000000001001);
        _systemRewardContract = ISystemReward(0x0000000000000000000000000000000000001002);
        // BAS defined addresses
        _stakingPoolContract = IStakingPool(0x0000000000000000000000000000000000007001);
        _governanceContract = IGovernance(0x0000000000000000000000000000000000007002);
        _chainConfigContract = IChainConfig(0x0000000000000000000000000000000000007003);
    }

    function initManually(
        IStaking stakingContract,
        ISlashingIndicator slashingIndicatorContract,
        ISystemReward systemRewardContract,
        IStakingPool stakingPoolContract,
        IGovernance governanceContract,
        IChainConfig chainConfigContract
    ) public whenNotInitialized {
        // BSC-compatible
        _stakingContract = stakingContract;
        _slashingIndicatorContract = slashingIndicatorContract;
        _systemRewardContract = systemRewardContract;
        // BAS-defined
        _stakingPoolContract = stakingPoolContract;
        _governanceContract = governanceContract;
        _chainConfigContract = chainConfigContract;
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

    modifier onlyZeroGasPrice() {
        require(tx.gasprice == 0, "InjectorContextHolder: only zero gas price");
        _;
    }

    modifier whenNotInitialized() {
        require(!_init, "OnlyInit: already initialized");
        _;
        _init = true;
    }

    modifier whenInitialized() {
        require(_init, "OnlyInit: not initialized yet");
        _;
    }

    modifier onlyOncePerBlock() {
        require(block.number > _operatingBlock, "InjectorContextHolder: only once per block");
        _;
        _operatingBlock = block.number;
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
