// SPDX-License-Identifier: Apache-2.0

/*
 * @title MerklePatriciaVerifier
 * @author Sam Mayo (sammayo888@gmail.com)
 *
 * @dev Library for verifing merkle patricia proofs.
 */
pragma solidity ^0.8.0;

import {RLPReader} from "./RLPReader.sol";

library MerklePatriciaProof {
    /*
   * @dev Verifies a merkle patricia proof.
   * @param value The terminating value in the trie.
   * @param encodedPath The path in the trie leading to value.
   * @param rlpParentNodes The rlp encoded stack of nodes.
   * @param root The root hash of the trie.
   * @return The boolean validity of the proof.
   */
    function verify(
        bytes32 value,
        bytes memory path,
        bytes memory siblingsRlp,
        bytes32 root
    ) internal pure returns (bool) {
        RLPReader.RLPItem[] memory siblings = RLPReader.toList(RLPReader.toRlpItem(siblingsRlp));

        bytes32 nodeKey = root;
        RLPReader.RLPItem[] memory currentNodeList;
        uint256 pathPtr = 0;

        bytes memory nibblePath = _getNibbleArray(path);
        if (nibblePath.length == 0) {
            return false;
        }
        for (uint256 i = 0; i < siblings.length; i++) {
            if (pathPtr > nibblePath.length) {
                return false;
            }
            if (nodeKey != keccak256(RLPReader.toRlpBytes(siblings[i]))) {
                return false;
            }
            currentNodeList = RLPReader.toList(siblings[i]);
            if (currentNodeList.length == 17) {
                if (pathPtr == nibblePath.length) {
                    return keccak256(RLPReader.toBytes(currentNodeList[16])) == value;
                }
                uint8 nextPathNibble = uint8(nibblePath[pathPtr]);
                if (nextPathNibble > 16) {
                    return false;
                }
                nodeKey = bytes32(RLPReader.toUintStrict(currentNodeList[nextPathNibble]));
                pathPtr += 1;
            } else if (currentNodeList.length == 2) {
                uint256 traversed = _nibblesToTraverse(RLPReader.toBytes(currentNodeList[0]), nibblePath, pathPtr);
                if (pathPtr + traversed == nibblePath.length) {
                    return keccak256(RLPReader.toBytes(currentNodeList[1])) == value;
                }
                if (traversed == 0) {
                    return false;
                }
                pathPtr += traversed;
                nodeKey = bytes32(RLPReader.toUintStrict(currentNodeList[1]));
            } else {
                return false;
            }
        }

        return false;
    }

    function _nibblesToTraverse(
        bytes memory encodedPartialPath,
        bytes memory path,
        uint256 pathPtr
    ) private pure returns (uint256) {
        uint256 len;
        // encodedPartialPath has elements that are each two hex characters (1 byte), but partialPath
        // and slicedPath have elements that are each one hex character (1 nibble)
        bytes memory partialPath = _getNibbleArray(encodedPartialPath);
        bytes memory slicedPath = new bytes(partialPath.length);

        // pathPtr counts nibbles in path
        // partialPath.length is a number of nibbles
        for (uint256 i = pathPtr; i < pathPtr + partialPath.length; i++) {
            bytes1 pathNibble = path[i];
            slicedPath[i - pathPtr] = pathNibble;
        }

        if (keccak256(partialPath) == keccak256(slicedPath)) {
            len = partialPath.length;
        } else {
            len = 0;
        }
        return len;
    }

    // bytes b must be hp encoded
    function _getNibbleArray(bytes memory b)
    private
    pure
    returns (bytes memory)
    {
        bytes memory nibbles;
        if (b.length == 0) {
            return nibbles;
        }
        uint8 offset;
        uint8 hpNibble = uint8(_getNthNibbleOfBytes(0, b));
        if (hpNibble == 1 || hpNibble == 3) {
            nibbles = new bytes(b.length * 2 - 1);
            bytes1 oddNibble = _getNthNibbleOfBytes(1, b);
            nibbles[0] = oddNibble;
            offset = 1;
        } else {
            nibbles = new bytes(b.length * 2 - 2);
            offset = 0;
        }
        for (uint256 i = offset; i < nibbles.length; i++) {
            nibbles[i] = _getNthNibbleOfBytes(i - offset + 2, b);
        }
        return nibbles;
    }

    function _getNthNibbleOfBytes(uint256 n, bytes memory str)
    private
    pure
    returns (bytes1)
    {
        return
        bytes1(
            n % 2 == 0 ? uint8(str[n / 2]) / 0x10 : uint8(str[n / 2]) % 0x10
        );
    }
}