// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

interface IGovernance {

    function getVotingSupply() external view returns (uint256);

    function getVotingPower(address validator) external view returns (uint256);
}
