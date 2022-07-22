// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "./IValidatorChecker.sol";

interface IProofVerificationFunction {

    struct BlockHeader {
        bytes32 blockHash;
        bytes32 parentHash;
        uint64 blockNumber;
        address coinbase;
        bytes32 receiptsRoot;
        bytes32 txsRoot;
        bytes32 stateRoot;
    }

    function verifyBlockWithoutQuorum(
        uint256 chainId,
        bytes calldata rawBlock,
        uint64 epochLength
    ) external view returns (
        bytes32 blockHash,
        address[] memory validatorSet,
        uint64 blockNumber
    );

    function verifyValidatorTransition(
        uint256 chainId,
        bytes[] calldata blockProofs,
        uint32 epochLength,
        IValidatorChecker validatorChecker
    ) external view returns (
        address[] memory newValidatorSet,
        uint64 epochNumber
    );

    function verifyBlockAndReachedQuorum(
        uint256 chainId,
        bytes[] calldata blockProofs,
        uint32 epochLength,
        IValidatorChecker validatorChecker
    ) external view returns (
        BlockHeader memory firstBlock
    );

    function checkReceiptProof(
        bytes calldata rawReceipt,
        bytes32 receiptRoot,
        bytes calldata proofSiblings,
        bytes calldata proofPath
    ) external view returns (bool);
}