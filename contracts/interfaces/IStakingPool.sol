// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

interface IStakingPool {

    function getStakedAmount(address validator, address staker) external view returns (uint256);

    function stake(address validator) external payable;

    function unstake(address validator, uint256 amount) external;

    function claimableRewards(address validator, address staker) external view returns (uint256);

    function claim(address validator) external;
}