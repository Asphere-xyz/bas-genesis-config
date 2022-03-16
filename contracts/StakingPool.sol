// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "./interfaces/IStaking.sol";
import "./interfaces/IInjector.sol";

contract StakingPool {

    event Stake(address staker, uint256 amount);
    event Unstake(address staker, uint256 amount);

    struct PendingUndelegate {
        uint256 amount;
        uint64 epoch;
    }

    // staking smart contract
    IStaking _stakingContract;
    address _validatorAddress;
    // allocates of shares
    mapping(address => uint256) private _shares;
    mapping(address => PendingUndelegate) private _undelegates;
    // staking params
    uint256 private _sharesSupply;
    uint256 private _totalStakedAmount;
    uint256 private _totalRewards;

    constructor(IStaking stakingContract, address validatorAddress) {
        _stakingContract = stakingContract;
        _validatorAddress = validatorAddress;
    }

    modifier onlyFromStakingContract() {
        require(msg.sender == address(_stakingContract));
        _;
    }

    modifier advanceStakingRewards() {
        {
            // claim rewards from staking contract
            uint256 claimedRewards = address(this).balance;
            _stakingContract.claimDelegatorFee(_validatorAddress);
            claimedRewards = address(this).balance - claimedRewards;
            // claimed rewards might be zero
            if (claimedRewards > 0) {
                _stakingContract.delegate{value : claimedRewards}(_validatorAddress);
                _totalRewards += claimedRewards;
            }
        }
        _;
    }

    function ratio() external view returns (uint256) {
        return _ratio();
    }

    function _ratio() internal view returns (uint256) {
        return _sharesSupply * 1e18 / (_totalStakedAmount + _totalRewards);
    }

    function sharesOf(address staker) external view returns (uint256) {
        return _shares[staker];
    }

    function stake(address staker) external payable onlyFromStakingContract advanceStakingRewards {
        uint256 shares = msg.value * _ratio() / 1e18;
        // increase total accumulated shares for the staker
        _shares[staker] += shares;
        // increase staking params for ratio calculation
        _totalStakedAmount += msg.value;
        _sharesSupply += shares;
        // emit event
        emit Stake(staker, msg.value);
    }

    function unstake(address staker, uint256 amount) external onlyFromStakingContract advanceStakingRewards {
        // make sure user doesn't have pending undelegates (we don't support it here)
        require(_undelegates[staker].epoch == 0, "StakingPool: undelegate pending");
        // calculate shares and make sure user have enough balance
        uint256 shares = amount * _ratio() / 1e18;
        require(shares <= _shares[staker], "StakingPool: not enough shares");
        // updates shares params
        _shares[staker] -= shares;
        _sharesSupply -= shares;
        _totalStakedAmount -= amount;
        // undelegate
        _stakingContract.undelegate(_validatorAddress, amount);
        // save new undelegate
        IChainConfig chainConfig = IInjector(address(_stakingContract)).getChainConfig();
        _undelegates[staker].amount = amount;
        _undelegates[staker].epoch = _stakingContract.nextEpoch() + chainConfig.getUndelegatePeriod();
    }

    function claimableRewards(address staker) external view returns (uint256) {
        return _undelegates[staker].amount;
    }

    function claim() external advanceStakingRewards {
        PendingUndelegate memory pendingUndelegate = _undelegates[msg.sender];
        uint256 amount = pendingUndelegate.amount;
        // do some checks
        require(pendingUndelegate.epoch >= 0, "StakingPool: nothing to claim");
        require(_stakingContract.currentEpoch() >= pendingUndelegate.epoch, "StakingPool: not ready");
        // remove pending claim
        delete _undelegates[msg.sender];
        // its safe to use call here (state is clear)
        payable(address(msg.sender)).transfer(amount);
    }
}