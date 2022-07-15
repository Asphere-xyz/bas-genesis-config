// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

abstract contract RetryMixin {

    error MethodNotFound();

    fallback() external payable {
        revert MethodNotFound();
    }

    receive() external payable {
        revert MethodNotFound();
    }
}