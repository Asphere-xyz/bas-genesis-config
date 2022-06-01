// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/utils/Create2.sol";

import "./InjectorContextHolder.sol";

contract RuntimeProxy is TransparentUpgradeableProxy {

    constructor(
        address runtimeUpgrade,
        bytes memory bytecode,
        bytes memory initializer
    ) TransparentUpgradeableProxy(_deployDefaultVersion(bytecode), runtimeUpgrade, "") {
        Address.functionDelegateCall(_implementation(), abi.encodeWithSelector(InjectorContextHolder.useDelayedInitializer.selector, initializer));
    }

    function _deployDefaultVersion(bytes memory bytecode) internal returns (address) {
        return Create2.deploy(0, bytes32(0x00), bytecode);
    }
}