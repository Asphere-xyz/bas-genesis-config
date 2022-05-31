// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/utils/Create2.sol";

import "./libs/SlotUtils.sol";

contract RuntimeProxy is ERC1967Proxy {

    bytes32 private constant _INITIALIZER_SLOT = keccak256("eip1967.proxy.initializer");

    constructor(address runtimeUpgrade, bytes memory bytecode, bytes memory initializerData) ERC1967Proxy(_deployDefaultVersion(bytecode), "") {
        // default proxy admin is runtime upgrade
        _changeAdmin(runtimeUpgrade);
        // save initializer
        SlotUtils.getBytesSlot(_INITIALIZER_SLOT).value = initializerData;
    }

    modifier onlyFromRuntimeUpgrade() {
        require(msg.sender == _getAdmin(), "RuntimeProxy: only runtime upgrade");
        _;
    }

    function init() external {
        bytes memory initializer = getInitializer();
        if (initializer.length > 0) {
            Address.functionDelegateCall(_implementation(), getInitializer(), "RuntimeProxy: call of init() failed");
        }
    }

    function getInitializer() public view returns (bytes memory result) {
        return SlotUtils.getBytesSlot(_INITIALIZER_SLOT).value;
    }

    function getCurrentVersion() external view returns (address) {
        return _implementation();
    }

    function upgradeToAndCall(address impl, bytes memory data) external onlyFromRuntimeUpgrade {
        _upgradeToAndCall(impl, data, false);
    }

    function _deployDefaultVersion(bytes memory bytecode) internal returns (address) {
        return Create2.deploy(0, bytes32(0x00), bytecode);
    }
}