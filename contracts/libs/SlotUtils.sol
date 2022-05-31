// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

library SlotUtils {

    struct BytesSlot {
        bytes value;
    }

    function getBytesSlot(bytes32 slot) internal pure returns (BytesSlot storage r) {
        assembly {
            r.slot := slot
        }
        return r;
    }
}