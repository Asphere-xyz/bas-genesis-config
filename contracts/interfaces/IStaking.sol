// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

interface IStakingRewardDistribution {

    function delegate(address validator) payable external;

    function undelegate(address validator, uint256 amount) external;

    function getValidatorDelegation(address validator, address delegator) external view returns (
        uint256 delegatedAmount,
        uint64 atEpoch
    );

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

interface IStakingValidatorManagement {

    function getValidators() external view returns (address[] memory);

    function deposit(address validator) external payable;

    function isValidatorActive(address validator) external view returns (bool);

    function isValidator(address validator) external view returns (bool);

    function getValidatorStatus(address validator) external view returns (
        address ownerAddress,
        uint8 status,
        uint256 totalDelegated,
        uint32 slashesCount,
        uint64 changedAt,
        uint64 jailedBefore,
        uint64 claimedAt,
        uint16 commissionRate,
        uint96 totalRewards
    );

    function getValidatorStatusAtEpoch(address validator, uint64 epoch) external view returns (
        address ownerAddress,
        uint8 status,
        uint256 totalDelegated,
        uint32 slashesCount,
        uint64 changedAt,
        uint64 jailedBefore,
        uint64 claimedAt,
        uint16 commissionRate,
        uint96 totalRewards
    );

    function getValidatorByOwner(address owner) external view returns (address);

    function registerValidator(address validator, bytes calldata votingKey, uint16 commissionRate) payable external;

    function addValidator(address validator, bytes calldata votingKey) external;

    function removeValidator(address validator) external;

    function activateValidator(address validator) external;

    function disableValidator(address validator) external;

    function releaseValidatorFromJail(address validator) external;

    function changeValidatorCommissionRate(address validator, uint16 commissionRate) external;

    function changeValidatorOwner(address validator, address newOwner) external;

    function changeVotingKey(address validatorAddress, bytes calldata newVotingKey) external;

    function slash(address validator) external;
}

interface IStaking is IStakingRewardDistribution, IStakingValidatorManagement {
}