// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "./IStaking.sol";
import "./ISlashingIndicator.sol";
import "./ISystemReward.sol";
import "./IContractDeployer.sol";
import "./IGovernance.sol";

interface IInjector {

    function getStaking() external view returns (IStaking);

    function getSlashingIndicator() external view returns (ISlashingIndicator);

    function getSystemReward() external view returns (ISystemReward);

    function getContractDeployer() external view returns (IContractDeployer);

    function getGovernance() external view returns (IGovernance);
}