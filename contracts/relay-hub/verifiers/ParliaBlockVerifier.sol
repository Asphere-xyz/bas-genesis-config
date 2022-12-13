// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "../interfaces/IProofVerificationFunction.sol";

import "./PoSaBlockVerifier.sol";

contract ParliaBlockVerifier is PoSaBlockVerifier {

    function verifyBlockWithoutQuorum(
        uint256 chainId,
        bytes calldata rawBlock,
        uint64 epochLength
    ) external view override returns (
        bytes32 blockHash,
        address[] memory validatorSet,
        uint64 blockNumber
    ) {
        BlockHeader memory blockHeader;
        (blockHeader, validatorSet) = _parseAndVerifyPoSaBlockHeader(chainId, rawBlock, epochLength);
        return (blockHeader.blockHash, validatorSet, blockHeader.blockNumber);
    }

    function verifyValidatorTransition(
        uint256 chainId,
        bytes[] calldata blockProofs,
        uint32 epochLength,
        IValidatorChecker validatorChecker
    ) external view returns (
        address[] memory newValidatorSet,
        uint64 epochNumber
    ) {
        BlockHeader memory firstBlock;
        (firstBlock, newValidatorSet) = _verifyBlocksAndReachedQuorum(chainId, blockProofs, epochLength, validatorChecker);
        require(firstBlock.blockNumber % epochLength == 0, "not epoch block");
        epochNumber = firstBlock.blockNumber / epochLength;
        return (newValidatorSet, epochNumber);
    }

    function verifyBlockAndReachedQuorum(
        uint256 chainId,
        bytes[] calldata blockProofs,
        uint32 epochLength,
        IValidatorChecker validatorChecker
    ) external view returns (
        BlockHeader memory firstBlock
    ) {
        address[] memory newValidatorSet;
        (firstBlock, newValidatorSet) = _verifyBlocksAndReachedQuorum(chainId, blockProofs, epochLength, validatorChecker);
        return firstBlock;
    }

    function checkReceiptProof(
        bytes calldata rawReceipt,
        bytes32 receiptRoot,
        bytes calldata proofSiblings,
        bytes calldata proofPath
    ) external view virtual override returns (bool) {
        return MerklePatriciaProof.verify(keccak256(rawReceipt), proofPath, proofSiblings, receiptRoot);
    }

    function _verifyBlocksAndReachedQuorum(
        uint256 chainId,
        bytes[] calldata blockProofs,
        uint64 epochLength,
        IValidatorChecker validatorChecker
    ) internal view returns (
        BlockHeader memory firstBlock,
        address [] memory newValidatorSet
    ) {
        // we must store somehow set of active validators to check is quorum reached
        address[] memory blockValidators = new address[](blockProofs.length);
        // check all blocks
        bytes32 parentHash;
        for (uint256 i = 0; i < blockProofs.length; i++) {
            (BlockHeader memory blockHeader, address[] memory validatorSet) = _parseAndVerifyPoSaBlockHeader(chainId, blockProofs[i], epochLength);
            address signer = blockHeader.coinbase;
            blockValidators[i] = signer;
            // first block is block with proof
            if (i == 0) {
                firstBlock = blockHeader;
                newValidatorSet = validatorSet;
            } else {
                require(blockHeader.parentHash == parentHash, "bad parent hash");
            }
            parentHash = blockHeader.blockHash;
        }
        // clac next epoch, for zero epoch we can't check previous validators
        uint64 epochNumber = firstBlock.blockNumber / epochLength;
        if (epochNumber > 0) {
            require(validatorChecker.checkValidatorsAndQuorumReached(chainId, blockValidators, firstBlock.blockNumber / epochLength - 1), "quorum not reached");
        }
        return (firstBlock, newValidatorSet);
    }

    function parseParliaBlockHeader(bytes calldata rawBlock) external pure returns (BlockHeader memory) {
        return _parsePoSaBlockHeader(rawBlock);
    }

    function extractParliaSigningData(
        bytes calldata blockProof,
        uint256 chainId,
        uint32 epochLength
    ) external view returns (
        BlockHeader memory result,
        address[] memory newValidatorSet
    ) {
        return _parseAndVerifyPoSaBlockHeader(chainId, blockProof, epochLength);
    }
}