// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

interface IValidatorChecker {

    function checkValidatorsAndQuorumReached(uint256 chainId, address[] memory validatorSet, uint64 epochNumber) external view returns (bool);
}