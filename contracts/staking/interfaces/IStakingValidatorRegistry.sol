// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "./IStakingEvents.sol";

interface IStakingValidatorRegistry is IStakingEvents {

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

    function forceUnJailValidator(address validatorAddress) external;

    function changeValidatorCommissionRate(address validator, uint16 commissionRate) external;

    function changeValidatorOwner(address validator, address newOwner) external;

    function changeVotingKey(address validatorAddress, bytes calldata newVotingKey) external;

    function slash(address validator) external;
}
