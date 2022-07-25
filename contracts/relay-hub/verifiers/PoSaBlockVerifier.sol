// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import "../interfaces/IProofVerificationFunction.sol";

import "../../common/MerklePatriciaProof.sol";
import "../../common/RLP.sol";

abstract contract PoSaBlockVerifier is IProofVerificationFunction {

    function _parseAndVerifyPoSaBlockHeader(
        uint256 chainId,
        bytes calldata rawBlock,
        uint64 epochLength
    ) internal virtual view returns (
        BlockHeader memory blockHeader,
        address[] memory newValidatorSet
    ) {
        // support of >64 kB headers might make code much more complicated and such blocks doesn't exist
        require(rawBlock.length <= 65535);
        // open RLP and calc block header length after the prefix (it should be block proof length -3)
        uint256 it = RLP.openRlp(rawBlock);
        uint256 originalLength = RLP.itemLength(it);
        it = RLP.beginIteration(it);
        // parent hash
        blockHeader.parentHash = RLP.toBytes32(it);
        it = RLP.next(it);
        // uncle hash
        it = RLP.next(it);
        // extract block coinbase
        address coinbase = RLP.toAddress(it);
        it = RLP.next(it);
        // state root
        blockHeader.stateRoot = RLP.toBytes32(it);
        it = RLP.next(it);
        // txs root
        blockHeader.txsRoot = RLP.toBytes32(it);
        it = RLP.next(it);
        // receipts root
        blockHeader.receiptsRoot = RLP.toBytes32(it);
        it = RLP.next(it);
        // bloom filter
        it = RLP.next(it);
        // slow skip for variadic fields: difficulty, number, gas limit, gas used, time
        it = RLP.next(it);
        blockHeader.blockNumber = uint64(RLP.toUint256(it, RLP.itemLength(it)));
        it = RLP.next(RLP.next(RLP.next(RLP.next(it))));
        // calculate and remember offsets for extra data begin and end
        uint256 beforeExtraDataOffset = it;
        it = RLP.next(it);
        uint256 afterExtraDataOffset = it;
        // create chain id and extra data RLPs
        uint256 oldExtraDataPrefixLength = RLP.prefixLength(beforeExtraDataOffset);
        uint256 newExtraDataPrefixLength;
        {
            uint256 newEstExtraDataLength = afterExtraDataOffset - beforeExtraDataOffset - oldExtraDataPrefixLength - 65;
            if (newEstExtraDataLength < 56) {
                newExtraDataPrefixLength = 1;
            } else {
                newExtraDataPrefixLength = 1 + RLP.uintRlpPrefixLength(newEstExtraDataLength);
            }
        }
        bytes memory chainRlp = RLP.uintToRlp(chainId);
        // form signing data from block proof
        bytes memory signingData = new bytes(chainRlp.length + originalLength - oldExtraDataPrefixLength + newExtraDataPrefixLength - 65);
        // init first 3 bytes of signing data with RLP prefix and encoded length
        {
            signingData[0] = 0xf9;
            uint256 bodyLength = signingData.length - 3;
            signingData[1] = bytes1(uint8(bodyLength >> 8));
            signingData[2] = bytes1(uint8(bodyLength >> 0));
        }
        // copy chain id rlp right after the prefix
        for (uint256 i = 0; i < chainRlp.length; i++) {
            signingData[3 + i] = chainRlp[i];
        }
        // copy block calldata to the signing data before extra data [0;extraData-65)
        assembly {
        // copy first bytes before extra data
            let dst := add(signingData, add(mload(chainRlp), 0x23)) // 0x20+3 (3 is a size of prefix for 64kB list)
            let src := add(rawBlock.offset, 3)
            let len := sub(beforeExtraDataOffset, src)
            calldatacopy(dst, src, len)
        // copy extra data with new prefix
            dst := add(add(dst, len), newExtraDataPrefixLength)
            src := add(beforeExtraDataOffset, oldExtraDataPrefixLength)
            len := sub(sub(sub(afterExtraDataOffset, beforeExtraDataOffset), oldExtraDataPrefixLength), 65)
            calldatacopy(dst, src, len)
        // copy rest (mix digest, nonce)
            dst := add(dst, len)
            src := afterExtraDataOffset
            len := 42 // its always 42 bytes
            calldatacopy(dst, src, len)
        }
        // patch extra data length inside RLP signing data
        {
            uint256 newExtraDataLength;
            uint256 patchExtraDataAt;
            assembly {
                newExtraDataLength := sub(sub(sub(afterExtraDataOffset, beforeExtraDataOffset), oldExtraDataPrefixLength), 65)
                patchExtraDataAt := sub(mload(signingData), add(add(newExtraDataLength, newExtraDataPrefixLength), 42))
            }
            // we don't need to cover more than 3 cases because we revert if block header >64kB
            if (newExtraDataPrefixLength == 4) {
                signingData[patchExtraDataAt + 0] = bytes1(uint8(0xb7 + 3));
                signingData[patchExtraDataAt + 1] = bytes1(uint8(newExtraDataLength >> 16));
                signingData[patchExtraDataAt + 2] = bytes1(uint8(newExtraDataLength >> 8));
                signingData[patchExtraDataAt + 3] = bytes1(uint8(newExtraDataLength >> 0));
            } else if (newExtraDataPrefixLength == 3) {
                signingData[patchExtraDataAt + 0] = bytes1(uint8(0xb7 + 2));
                signingData[patchExtraDataAt + 1] = bytes1(uint8(newExtraDataLength >> 8));
                signingData[patchExtraDataAt + 2] = bytes1(uint8(newExtraDataLength >> 0));
            } else if (newExtraDataPrefixLength == 2) {
                signingData[patchExtraDataAt + 0] = bytes1(uint8(0xb7 + 1));
                signingData[patchExtraDataAt + 1] = bytes1(uint8(newExtraDataLength >> 0));
            } else if (newExtraDataLength < 56) {
                signingData[patchExtraDataAt + 0] = bytes1(uint8(0x80 + newExtraDataLength));
            }
            // else can't be here, its unreachable
        }
        // save signature
        bytes memory signature = new bytes(65);
        assembly {
            calldatacopy(add(signature, 0x20), sub(afterExtraDataOffset, 65), 65)
        }
        // recover signer from signature (genesis block doesn't have signature)
        if (blockHeader.blockNumber != 0) {
            if (signature[64] == bytes1(uint8(1))) {
                signature[64] = bytes1(uint8(28));
            } else {
                signature[64] = bytes1(uint8(27));
            }
            blockHeader.coinbase = ECDSA.recover(keccak256(signingData), signature);
            require(blockHeader.coinbase == coinbase, "bad coinbase");
        }
        // parse validators for zero block epoch
        if (blockHeader.blockNumber % epochLength == 0) {
            uint256 totalValidators = (afterExtraDataOffset - beforeExtraDataOffset + oldExtraDataPrefixLength - 65 - 32) / 20;
            newValidatorSet = new address[](totalValidators);
            for (uint256 i = 0; i < totalValidators; i++) {
                uint256 validator;
                assembly {
                    validator := calldataload(add(add(add(beforeExtraDataOffset, oldExtraDataPrefixLength), mul(i, 20)), 32))
                }
                newValidatorSet[i] = address(uint160(validator >> 96));
            }
        }
        // calc block hash
        blockHeader.blockHash = keccak256(rawBlock);
        return (blockHeader, newValidatorSet);
    }

    function _parsePoSaBlockHeader(bytes calldata rawBlock) internal pure returns (BlockHeader memory blockHeader) {
        uint256 it = RLP.beginRlp(rawBlock);
        // parent hash, uncle hash
        it = RLP.next(it);
        blockHeader.parentHash = RLP.toBytes32(it);
        it = RLP.next(it);
        // coinbase
        blockHeader.coinbase = RLP.toAddress(it);
        it = RLP.next(it);
        // state root, transactions root, receipts root
        blockHeader.stateRoot = RLP.toBytes32(it);
        it = RLP.next(it);
        blockHeader.txsRoot = RLP.toBytes32(it);
        it = RLP.next(it);
        blockHeader.receiptsRoot = RLP.toBytes32(it);
        it = RLP.next(it);
        // bloom, difficulty
        it = RLP.next(it);
        it = RLP.next(it);
        // block number, gas limit, gas used, time
        blockHeader.blockNumber = uint64(RLP.toUint256(it, RLP.itemLength(it)));
        it = RLP.next(it);
        it = RLP.next(it);
        it = RLP.next(it);
        it = RLP.next(it);
        // extra data
        it = RLP.next(it);
        // mix digest, nonce
        it = RLP.next(it);
        it = RLP.next(it);
        // calc block hash
        blockHeader.blockHash = keccak256(rawBlock);
        return blockHeader;
    }
}