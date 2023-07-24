// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "./IStakingEvents.sol";

interface IStakingRewardDistribution is IStakingEvents {
    function currentEpoch() external view returns (uint64);

    function nextEpoch() external view returns (uint64);

    function deposit(address validator) external payable;

    function getValidatorDelegation(address validator, address delegator) external view returns (
        uint256 delegatedAmount,
        uint64 atEpoch
    );

    function delegate(address validator) payable external;

    function undelegate(address validator, uint256 amount) external;

    function getValidatorFee(address validator) external view returns (uint256);

    function getPendingValidatorFee(address validator) external view returns (uint256);

    function claimValidatorFee(address validator) external;

    function getDelegatorFee(address validator, address delegator) external view returns (uint256);

    function getPendingDelegatorFee(address validator, address delegator) external view returns (uint256);

    function claimDelegatorFee(address validator) external;

    function calcAvailableForRedelegateAmount(address validator, address delegator) external view returns (uint256 amountToStake, uint256 rewardsDust);

    function claimPendingUndelegates(address validator) external;

    function redelegateDelegatorFee(address validator) external;
}