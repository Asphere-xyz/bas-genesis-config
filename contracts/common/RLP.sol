// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.6;

library RLP {

    uint8 public constant STRING_SHORT_START = 0x80;
    uint8 public constant STRING_LONG_START = 0xb8;
    uint8 public constant LIST_SHORT_START = 0xc0;
    uint8 public constant LIST_LONG_START = 0xf8;
    uint8 public constant WORD_SIZE = 32;

    function openRlp(bytes calldata rawRlp) internal pure returns (uint256 iter) {
        uint256 rawRlpOffset;
        assembly {
            rawRlpOffset := rawRlp.offset
        }
        return rawRlpOffset;
    }

    function beginRlp(bytes calldata rawRlp) internal pure returns (uint256 iter) {
        uint256 rawRlpOffset;
        assembly {
            rawRlpOffset := rawRlp.offset
        }
        return rawRlpOffset + _payloadOffset(rawRlpOffset);
    }

    function lengthRlp(bytes calldata rawRlp) internal pure returns (uint256 iter) {
        uint256 rawRlpOffset;
        assembly {
            rawRlpOffset := rawRlp.offset
        }
        return itemLength(rawRlpOffset);
    }

    function beginIteration(uint256 offset) internal pure returns (uint256 iter) {
        return offset + _payloadOffset(offset);
    }

    function next(uint256 iter) internal pure returns (uint256 nextIter) {
        return iter + itemLength(iter);
    }

    function payloadLen(uint256 ptr, uint256 len) internal pure returns (uint256) {
        return len - _payloadOffset(ptr);
    }

    function toAddress(uint256 ptr) internal pure returns (address) {
        return address(uint160(toUint(ptr, 21)));
    }

    function toBytes32(uint256 ptr) internal pure returns (bytes32) {
        return bytes32(toUint(ptr, 33));
    }

    function toRlpBytes(uint256 ptr) internal pure returns (bytes memory) {
        uint256 length = itemLength(ptr);
        bytes memory result = new bytes(length);
        if (result.length == 0) {
            return result;
        }
        ptr = beginIteration(ptr);
        assembly {
            calldatacopy(add(0x20, result), ptr, length)
        }
        return result;
    }

    function toRlpBytesKeccak256(uint256 ptr) internal pure returns (bytes32) {
        return keccak256(toRlpBytes(ptr));
    }
    
    function toBytes(uint256 ptr) internal pure returns (bytes memory) {
        uint256 offset = _payloadOffset(ptr);
        uint256 length = itemLength(ptr) - offset;
        bytes memory result = new bytes(length);
        if (result.length == 0) {
            return result;
        }
        ptr = beginIteration(ptr);
        assembly {
            calldatacopy(add(0x20, result), add(ptr, offset), length)
        }
        return result;
    }

    function toUint256(uint256 ptr, uint256 len) internal pure returns (uint256) {
        return toUint(ptr, len);
    }

    function uintToRlp(uint256 value) internal pure returns (bytes memory result) {
        // zero can be encoded as zero or empty array, go-ethereum's encodes as empty array
        if (value == 0) {
            result = new bytes(1);
            result[0] = 0x80;
            return result;
        }
        // encode value
        if (value <= 0x7f) {
            result = new bytes(1);
            result[0] = bytes1(uint8(value));
            return result;
        } else if (value < (1 << 8)) {
            result = new bytes(2);
            result[0] = 0x81;
            result[1] = bytes1(uint8(value));
            return result;
        } else if (value < (1 << 16)) {
            result = new bytes(3);
            result[0] = 0x82;
            result[1] = bytes1(uint8(value >> 8));
            result[2] = bytes1(uint8(value));
            return result;
        } else if (value < (1 << 24)) {
            result = new bytes(4);
            result[0] = 0x83;
            result[1] = bytes1(uint8(value >> 16));
            result[2] = bytes1(uint8(value >> 8));
            result[3] = bytes1(uint8(value));
            return result;
        } else if (value < (1 << 32)) {
            result = new bytes(5);
            result[0] = 0x84;
            result[1] = bytes1(uint8(value >> 24));
            result[2] = bytes1(uint8(value >> 16));
            result[3] = bytes1(uint8(value >> 8));
            result[4] = bytes1(uint8(value));
            return result;
        } else if (value < (1 << 40)) {
            result = new bytes(6);
            result[0] = 0x85;
            result[1] = bytes1(uint8(value >> 32));
            result[2] = bytes1(uint8(value >> 24));
            result[3] = bytes1(uint8(value >> 16));
            result[4] = bytes1(uint8(value >> 8));
            result[5] = bytes1(uint8(value));
            return result;
        } else if (value < (1 << 48)) {
            result = new bytes(7);
            result[0] = 0x86;
            result[1] = bytes1(uint8(value >> 40));
            result[2] = bytes1(uint8(value >> 32));
            result[3] = bytes1(uint8(value >> 24));
            result[4] = bytes1(uint8(value >> 16));
            result[5] = bytes1(uint8(value >> 8));
            result[6] = bytes1(uint8(value));
            return result;
        } else if (value < (1 << 56)) {
            result = new bytes(8);
            result[0] = 0x87;
            result[1] = bytes1(uint8(value >> 48));
            result[2] = bytes1(uint8(value >> 40));
            result[3] = bytes1(uint8(value >> 32));
            result[4] = bytes1(uint8(value >> 24));
            result[5] = bytes1(uint8(value >> 16));
            result[6] = bytes1(uint8(value >> 8));
            result[7] = bytes1(uint8(value));
            return result;
        } else {
            result = new bytes(9);
            result[0] = 0x88;
            result[1] = bytes1(uint8(value >> 56));
            result[2] = bytes1(uint8(value >> 48));
            result[3] = bytes1(uint8(value >> 40));
            result[4] = bytes1(uint8(value >> 32));
            result[5] = bytes1(uint8(value >> 24));
            result[6] = bytes1(uint8(value >> 16));
            result[7] = bytes1(uint8(value >> 8));
            result[8] = bytes1(uint8(value));
            return result;
        }
    }

    function uintRlpPrefixLength(uint256 value) internal pure returns (uint256 len) {
        if (value < (1 << 8)) {
            return 1;
        } else if (value < (1 << 16)) {
            return 2;
        } else if (value < (1 << 24)) {
            return 3;
        } else if (value < (1 << 32)) {
            return 4;
        } else if (value < (1 << 40)) {
            return 5;
        } else if (value < (1 << 48)) {
            return 6;
        } else if (value < (1 << 56)) {
            return 7;
        } else {
            return 8;
        }
    }

    function toUint(uint256 ptr, uint256 len) internal pure returns (uint256) {
        require(len > 0 && len <= 33);
        uint256 offset = _payloadOffset(ptr);
        uint256 result;
        assembly {
            result := calldataload(add(ptr, offset))
        // cut off redundant bytes
            result := shr(mul(8, sub(32, sub(len, offset))), result)
        }
        return result;
    }

    function toUintStrict(uint256 ptr) internal pure returns (uint256) {
        // one byte prefix
        uint256 result;
        assembly {
            result := calldataload(add(ptr, 1))
        }
        return result;
    }

    function rawDataPtr(uint256 ptr) internal pure returns (uint256) {
        return ptr + _payloadOffset(ptr);
    }

    // @return entire rlp item byte length
    function itemLength(uint ptr) internal pure returns (uint256) {
        uint256 itemLen;
        uint256 byte0;
        assembly {
            byte0 := byte(0, calldataload(ptr))
        }

        if (byte0 < STRING_SHORT_START)
            itemLen = 1;
        else if (byte0 < STRING_LONG_START)
            itemLen = byte0 - STRING_SHORT_START + 1;
        else if (byte0 < LIST_SHORT_START) {
            assembly {
                let byteLen := sub(byte0, 0xb7) // # of bytes the actual length is
                ptr := add(ptr, 1) // skip over the first byte
                let dataLen := shr(mul(8, sub(32, byteLen)), calldataload(ptr))
                itemLen := add(dataLen, add(byteLen, 1))
            }
        }
        else if (byte0 < LIST_LONG_START) {
            itemLen = byte0 - LIST_SHORT_START + 1;
        }
        else {
            assembly {
                let byteLen := sub(byte0, 0xf7)
                ptr := add(ptr, 1)

                let dataLen := shr(mul(8, sub(32, byteLen)), calldataload(ptr))
                itemLen := add(dataLen, add(byteLen, 1))
            }
        }

        return itemLen;
    }

    function prefixLength(uint256 ptr) internal pure returns (uint256) {
        return _payloadOffset(ptr);
    }

    function estimatePrefixLength(uint256 length) internal pure returns (uint256) {
        if (length == 0) return 1;
        if (length == 1) return 1;
        if (length < 0x38) {
            return 1;
        }
        return 0;
    }

    // @return number of bytes until the data
    function _payloadOffset(uint256 ptr) private pure returns (uint256) {
        uint256 byte0;
        assembly {
            byte0 := byte(0, calldataload(ptr))
        }

        if (byte0 < STRING_SHORT_START)
            return 0;
        else if (byte0 < STRING_LONG_START || (byte0 >= LIST_SHORT_START && byte0 < LIST_LONG_START))
            return 1;
        else if (byte0 < LIST_SHORT_START)
            return byte0 - (STRING_LONG_START - 1) + 1;
        else
            return byte0 - (LIST_LONG_START - 1) + 1;
    }
}
