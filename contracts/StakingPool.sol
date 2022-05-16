// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "./interfaces/IStaking.sol";
import "./interfaces/IStakingPool.sol";
import "./interfaces/IInjector.sol";

import "./Injector.sol";
import "./Staking.sol";

contract StakingPool is InjectorContextHolder, IStakingPool {

    /**
     * This value must the same as in Staking smart contract
     */
    uint256 internal constant BALANCE_COMPACT_PRECISION = 1e10;

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

    constructor(bytes memory constructorParams) InjectorContextHolder(constructorParams) {
    }

    function ctor() external whenNotInitialized {
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
        (uint256 stakedAmount, uint256 dustRewards) = _calcUnclaimedDelegatorFee(validatorPool);
        validatorPool.totalStakedAmount += stakedAmount;
        validatorPool.dustRewards = dustRewards;
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
            (uint256 stakedAmount, uint256 dustRewards) = _calcUnclaimedDelegatorFee(validatorPool);
            _stakingContract.claimDelegatorFee(validator);
            // re-delegate just arrived rewards
            if (stakedAmount > 0) {
                _stakingContract.delegate{value : stakedAmount}(validator);
            }
            // increase total accumulated rewards
            validatorPool.totalStakedAmount += stakedAmount;
            validatorPool.dustRewards = dustRewards;
            // save validator pool changes
            _validatorPools[validator] = validatorPool;
        }
        _;
    }

    function _getValidatorPool(address validator) internal view returns (ValidatorPool memory) {
        ValidatorPool memory validatorPool = _validatorPools[validator];
        validatorPool.validatorAddress = validator;
        return validatorPool;
    }

    function _calcUnclaimedDelegatorFee(ValidatorPool memory validatorPool) internal view returns (uint256 stakedAmount, uint256 dustRewards) {
        uint256 unclaimedRewards = _stakingContract.getDelegatorFee(validatorPool.validatorAddress, address(this));
        // adjust values based on total dust and pending unstakes
        unclaimedRewards += validatorPool.dustRewards;
        unclaimedRewards -= validatorPool.pendingUnstake;
        // split balance into stake and dust
        stakedAmount = (unclaimedRewards / BALANCE_COMPACT_PRECISION) * BALANCE_COMPACT_PRECISION;
        if (stakedAmount < _chainConfigContract.getMinStakingAmount()) {
            return (0, unclaimedRewards);
        }
        return (stakedAmount, unclaimedRewards - stakedAmount);
    }

    function _calcRatio(ValidatorPool memory validatorPool) internal view returns (uint256) {
        (uint256 stakedAmount, /*uint256 dustRewards*/) = _calcUnclaimedDelegatorFee(validatorPool);
        uint256 stakeWithRewards = validatorPool.totalStakedAmount + stakedAmount;
        if (stakeWithRewards == 0) {
            return 1e18;
        }
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
        _stakingContract.delegate{value : msg.value}(validator);
        // emit event
        emit Stake(validator, msg.sender, msg.value);
    }

    function unstake(address validator, uint256 amount) external advanceStakingRewards(validator) override {
        ValidatorPool memory validatorPool = _getValidatorPool(validator);
        require(validatorPool.totalStakedAmount > 0, "StakingPool: nothing to unstake");
        // make sure user doesn't have pending undelegates (we don't support it here)
        require(_pendingUnstakes[validator][msg.sender].epoch == 0, "StakingPool: undelegate pending");
        // calculate shares and make sure user have enough balance
        uint256 shares = amount * _calcRatio(validatorPool) / 1e18;
        require(shares <= _stakerShares[validator][msg.sender], "StakingPool: not enough shares");
        // save new undelegate
        IChainConfig chainConfig = IInjector(address(_stakingContract)).getChainConfig();
        _pendingUnstakes[validator][msg.sender] = PendingUnstake({
        amount : amount,
        shares : shares,
        epoch : _stakingContract.nextEpoch() + chainConfig.getUndelegatePeriod()
        });
        validatorPool.pendingUnstake += amount;
        _validatorPools[validator] = validatorPool;
        // undelegate
        _stakingContract.undelegate(validator, amount);
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
        // make sure user have pending unstake
        require(pendingUnstake.epoch > 0, "StakingPool: nothing to claim");
        require(pendingUnstake.epoch <= _stakingContract.currentEpoch(), "StakingPool: not ready");
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
        require(address(this).balance >= amount, "StakingPool: not enough balance");
        payable(address(msg.sender)).transfer(amount);
        // emit event
        emit Claim(validator, msg.sender, amount);
    }

    receive() external payable {
        require(address(msg.sender) == address(_stakingContract), "StakingPool: not a staking contract");
    }
}