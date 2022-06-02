// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "./interfaces/IInjectorContextHolder.sol";
import "./interfaces/IStaking.sol";
import "./interfaces/IStakingPool.sol";

import "./InjectorContextHolder.sol";
import "./Staking.sol";

contract StakingPool is InjectorContextHolder, IStakingPool {

    event Stake(address indexed validator, address indexed staker, uint256 amount);
    event Unstake(address indexed validator, address indexed staker, uint256 amount);
    event Claim(address indexed validator, address indexed staker, uint256 amount);

    struct ValidatorPool {
        address validatorAddress;
        uint256 sharesSupply;
        uint256 totalStakedAmount;
        uint256 dustRewards;
        uint256 pendingUnstake;
    }

    struct PendingUnstake {
        uint256 amount;
        uint256 shares;
        uint64 epoch;
    }

    // validator pools (validator => pool)
    mapping(address => ValidatorPool) internal _validatorPools;
    // pending undelegates (validator => staker => pending unstake)
    mapping(address => mapping(address => PendingUnstake)) _pendingUnstakes;
    // allocated shares (validator => staker => shares)
    mapping(address => mapping(address => uint256)) _stakerShares;

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

    function initialize() external initializer {
    }

    function getStakedAmount(address validator, address staker) external view returns (uint256) {
        ValidatorPool memory validatorPool = _getValidatorPool(validator);
        return _stakerShares[validator][staker] * 1e18 / _calcRatio(validatorPool);
    }

    function getShares(address validator, address staker) external view returns (uint256) {
        return _stakerShares[validator][staker];
    }

    function getValidatorPool(address validator) external view returns (ValidatorPool memory) {
        ValidatorPool memory validatorPool = _getValidatorPool(validator);
        (uint256 amountToStake, uint256 dustRewards) = _calcUnclaimedDelegatorFee(validatorPool);
        validatorPool.totalStakedAmount += amountToStake;
        validatorPool.dustRewards += dustRewards;
        return validatorPool;
    }

    function getRatio(address validator) external view returns (uint256) {
        ValidatorPool memory validatorPool = _getValidatorPool(validator);
        return _calcRatio(validatorPool);
    }

    modifier advanceStakingRewards(address validator) {
        {
            ValidatorPool memory validatorPool = _getValidatorPool(validator);
            // claim rewards from staking contract
            (uint256 amountToStake, uint256 dustRewards) = _calcUnclaimedDelegatorFee(validatorPool);
            // increase total accumulated rewards
            validatorPool.totalStakedAmount += amountToStake;
            validatorPool.dustRewards += dustRewards;
            // save validator pool changes
            _validatorPools[validator] = validatorPool;
            // if we have something to redelegate then do this right now
            if (amountToStake > 0) {
                _STAKING_CONTRACT.redelegateDelegatorFee(validatorPool.validatorAddress);
            }
        }
        _;
    }

    function _getValidatorPool(address validator) internal view returns (ValidatorPool memory) {
        ValidatorPool memory validatorPool = _validatorPools[validator];
        validatorPool.validatorAddress = validator;
        return validatorPool;
    }

    function _calcUnclaimedDelegatorFee(ValidatorPool memory validatorPool) internal view returns (uint256 amountToStake, uint256 dustRewards) {
        return _STAKING_CONTRACT.calcAvailableForRedelegateAmount(validatorPool.validatorAddress, address(this));
    }

    function _calcRatio(ValidatorPool memory validatorPool) internal view returns (uint256) {
        (uint256 stakedAmount, /*uint256 dustRewards*/) = _calcUnclaimedDelegatorFee(validatorPool);
        uint256 stakeWithRewards = validatorPool.totalStakedAmount + stakedAmount;
        if (stakeWithRewards == 0) {
            return 1e18;
        }
        // we're doing upper rounding here
        return (validatorPool.sharesSupply * 1e18 + stakeWithRewards - 1) / stakeWithRewards;
    }

    function stake(address validator) external payable advanceStakingRewards(validator) override {
        ValidatorPool memory validatorPool = _getValidatorPool(validator);
        uint256 shares = msg.value * _calcRatio(validatorPool) / 1e18;
        // increase total accumulated shares for the staker
        _stakerShares[validator][msg.sender] += shares;
        // increase staking params for ratio calculation
        validatorPool.totalStakedAmount += msg.value;
        validatorPool.sharesSupply += shares;
        // save validator pool
        _validatorPools[validator] = validatorPool;
        // delegate these tokens to the staking contract
        _STAKING_CONTRACT.delegate{value : msg.value}(validator);
        // emit event
        emit Stake(validator, msg.sender, msg.value);
    }

    function unstake(address validator, uint256 amount) external advanceStakingRewards(validator) override {
        ValidatorPool memory validatorPool = _getValidatorPool(validator);
        require(validatorPool.totalStakedAmount > 0, "nothing to unstake");
        // make sure user doesn't have pending undelegates (we don't support it here)
        require(_pendingUnstakes[validator][msg.sender].epoch == 0, "undelegate pending");
        // calculate shares and make sure user have enough balance
        uint256 shares = amount * _calcRatio(validatorPool) / 1e18;
        require(shares <= _stakerShares[validator][msg.sender], "not enough shares");
        // save new undelegate
        _pendingUnstakes[validator][msg.sender] = PendingUnstake({
        amount : amount,
        shares : shares,
        epoch : _STAKING_CONTRACT.nextEpoch() + _CHAIN_CONFIG_CONTRACT.getUndelegatePeriod()
        });
        validatorPool.pendingUnstake += amount;
        _validatorPools[validator] = validatorPool;
        // undelegate
        _STAKING_CONTRACT.undelegate(validator, amount);
        // emit event
        emit Unstake(validator, msg.sender, amount);
    }

    function claimableRewards(address validator, address staker) external view override returns (uint256) {
        return _pendingUnstakes[validator][staker].amount;
    }

    function claim(address validator) external advanceStakingRewards(validator) override {
        PendingUnstake memory pendingUnstake = _pendingUnstakes[validator][msg.sender];
        uint256 amount = pendingUnstake.amount;
        uint256 shares = pendingUnstake.shares;
        // claim undelegate rewards
        _STAKING_CONTRACT.claimPendingUndelegates(validator);
        // make sure user have pending unstake
        require(pendingUnstake.epoch > 0, "nothing to claim");
        require(pendingUnstake.epoch <= _STAKING_CONTRACT.currentEpoch(), "not ready");
        // updates shares and validator pool params
        _stakerShares[validator][msg.sender] -= shares;
        ValidatorPool memory validatorPool = _getValidatorPool(validator);
        validatorPool.sharesSupply -= shares;
        validatorPool.totalStakedAmount -= amount;
        validatorPool.pendingUnstake -= amount;
        _validatorPools[validator] = validatorPool;
        // remove pending claim
        delete _pendingUnstakes[validator][msg.sender];
        // its safe to use call here (state is clear)
        require(address(this).balance >= amount, "not enough balance");
        payable(address(msg.sender)).transfer(amount);
        // emit event
        emit Claim(validator, msg.sender, amount);
    }

    receive() external payable {
        require(address(msg.sender) == address(_STAKING_CONTRACT), "not a staking contract");
    }
}