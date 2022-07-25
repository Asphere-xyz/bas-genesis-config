// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "../interfaces/IProofVerificationFunction.sol";

contract FakeBlockVerifier is IProofVerificationFunction {

    function verifyBlockWithoutQuorum(
        uint256,
        bytes calldata,
        uint64
    ) external pure returns (
        bytes32 blockHash,
        address[] memory validatorSet,
        uint64 blockNumber
    ) {
    }

    function verifyValidatorTransition(
        uint256,
        bytes[] calldata,
        uint32,
        IValidatorChecker
    ) external pure returns (
        address[] memory newValidatorSet,
        uint64 epochNumber
    ) {
    }

    function verifyBlockAndReachedQuorum(
        uint256,
        bytes[] calldata,
        uint32,
        IValidatorChecker
    ) external pure returns (
        BlockHeader memory firstBlock
    ) {
        return firstBlock;
    }

    function checkReceiptProof(
        bytes calldata,
        bytes32,
        bytes calldata,
        bytes calldata
    ) external pure returns (bool) {
        return true;
    }
}