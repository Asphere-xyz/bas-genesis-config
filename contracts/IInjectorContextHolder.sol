// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

interface IInjectorContextHolder {

    function useDelayedInitializer(bytes memory delayedInitializer) external;

    function init() external;

    function isInitialized() external view returns (bool);
}