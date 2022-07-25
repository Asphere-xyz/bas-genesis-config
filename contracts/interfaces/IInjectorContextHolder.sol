// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "./ISlashingIndicator.sol";
import "./ISystemReward.sol";
import "./IGovernance.sol";
import "./IStaking.sol";
import "./IDeployerProxy.sol";
import "./IStakingPool.sol";
import "./IChainConfig.sol";

interface IInjectorContextHolder {

    function useDelayedInitializer(bytes memory delayedInitializer) external;

    function init() external;

    function isInitialized() external view returns (bool);
}