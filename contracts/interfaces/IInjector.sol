// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "./IStaking.sol";
import "./ISlashingIndicator.sol";
import "./ISystemReward.sol";
import "./IGovernance.sol";

interface IInjector {

    function init() external;

    function isInitialized() external view returns (bool);
}