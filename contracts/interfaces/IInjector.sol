// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "./ISlashingIndicator.sol";
import "./ISystemReward.sol";
import "./IGovernance.sol";
import "./IStaking.sol";
import "./IDeployerProxy.sol";
import "./IStakingPool.sol";
import "./IChainConfig.sol";

interface IInjector {

    function init() external;

    function isInitialized() external view returns (bool);

    function getStaking() external view returns (IStaking);

    function getSlashingIndicator() external view returns (ISlashingIndicator);

    function getSystemReward() external view returns (ISystemReward);

    function getStakingPool() external view returns (IStakingPool);

    function getGovernance() external view returns (IGovernance);

    function getChainConfig() external view returns (IChainConfig);
}