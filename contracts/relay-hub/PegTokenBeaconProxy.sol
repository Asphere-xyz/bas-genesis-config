// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.6;

import {IBeacon, Proxy, ERC1967Upgrade} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

/**
 * This is a simple beacon proxy with only one modification: it can be created w/o initial beacon reference, its
 * required for us to optimize gas costs for storing bytecode hash of this smart contract.
 */
contract PegTokenBeaconProxy is Proxy, ERC1967Upgrade {

    address internal constant ZERO_ADDRESS = 0x0000000000000000000000000000000000000000;

    constructor() payable {
        assert(_BEACON_SLOT == bytes32(uint256(keccak256("eip1967.proxy.beacon")) - 1));
    }

    function initialize(address beacon) external {
        // make sure beacon is not set (it can't be changed in the future)
        require(_getBeacon() == ZERO_ADDRESS, "only once");
        // set new beacon
        _upgradeBeaconToAndCall(beacon, bytes(""), false);
    }

    /**
     * @dev Returns the current implementation address of the associated beacon.
     */
    function _implementation() internal view virtual override returns (address) {
        return IBeacon(_getBeacon()).implementation();
    }
}