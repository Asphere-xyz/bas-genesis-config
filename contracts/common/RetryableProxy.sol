// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/proxy/Proxy.sol";

abstract contract RetryableProxy is Proxy {

    error MethodNotFound();

    function _delegate(address implementation) internal override {
        assembly {
            // call contract and store result at 0 address
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), implementation, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            // check possible results
            switch result
            case 0 {
                // if return code equal to keccak256("MethodNotFound()") then don't revert
                if iszero(eq(shr(0xe0, mload(0)), 0x06c78984)) {
                    revert(0, returndatasize())
                }
            }
            default {
                return(0, returndatasize())
            }
        }
    }

    function _fallback() internal virtual override {
        // if you override this method then revert must exist in the end of the method
        revert MethodNotFound();
    }

    function _implementation() internal pure override returns (address) {
        return 0x0000000000000000000000000000000000000000;
    }
}