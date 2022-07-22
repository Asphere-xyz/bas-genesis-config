// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "./ParliaBlockVerifier.sol";

contract EmbeddedParliaBlockVerifier is ParliaBlockVerifier {

    address constant internal VERIFY_PARLIA_BLOCK_PRECOMPILE = address(0x0000000000000000000000000000004241530001);

    struct EmbeddedBlockVerifiedResult {
        bytes32 blockHash;
        bytes32 parentHash;
        uint64 blockNumber;
        address coinbase;
        bytes32 receiptsRoot;
        bytes32 txsRoot;
        bytes32 stateRoot;
        address[] newValidatorSet;
    }

    function _parseAndVerifyPoSaBlockHeader(
        uint256 chainId,
        bytes calldata rawBlock,
        uint64 epochLength
    ) internal virtual override view returns (
        BlockHeader memory blockHeader,
        address[] memory newValidatorSet
    ) {
        bytes memory input = abi.encode(chainId, rawBlock, epochLength);
        bytes memory output = new bytes(rawBlock.length);
        assembly {
            let status := staticcall(0, 0x0000000000000000000000000000004241530001, add(input, 0x20), mload(input), add(output, 0x20), mload(output))
            switch status
            case 0 {
                revert(add(output, 0x20), returndatasize())
            }
        }
        // TODO: "i think this decode can be optimized a lot"
        EmbeddedBlockVerifiedResult memory result = abi.decode(output, (EmbeddedBlockVerifiedResult));
        blockHeader.blockHash = result.blockHash;
        blockHeader.parentHash = result.parentHash;
        blockHeader.blockNumber = result.blockNumber;
        blockHeader.coinbase = result.coinbase;
        blockHeader.receiptsRoot = result.receiptsRoot;
        blockHeader.txsRoot = result.txsRoot;
        blockHeader.stateRoot = result.stateRoot;
        return (blockHeader, result.newValidatorSet);
    }
}