// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.6;

import {IBridgeHandler, ICrossChainBridge} from "../interfaces/IBridgeHandler.sol";

import {PegTokenBeaconProxy, IBeacon} from "../PegTokenBeaconProxy.sol";
import {ERC20PegToken} from "./ERC20PegToken.sol";

contract ERC20TokenHandler is IBridgeHandler, IBeacon {

    address private immutable _tokenTemplate;
    bytes32 private immutable _proxyBytecodeHash;
    address private immutable _originalThis;

    constructor() {
        _tokenTemplate = _factoryTokenTemplate();
        _proxyBytecodeHash = keccak256(type(PegTokenBeaconProxy).creationCode);
        _originalThis = address(this);
    }

    function _factoryTokenTemplate() internal virtual returns (address) {
        return address(new ERC20PegToken());
    }

    function calcPegTokenAddress(address bridgeAddress, address fromToken) external view override returns (address) {
        bytes32 hash = keccak256(abi.encodePacked(uint8(0xff), bridgeAddress, bytes32(bytes20(fromToken)), _proxyBytecodeHash));
        return address(bytes20(hash << 96));
    }

    function factoryPegToken(address fromToken, ICrossChainBridge.MetaData memory metaData, uint256 fromChain) external override returns (address) {
        // we must use delegate call because we need to deploy new contract from bridge contract to have valid address
        bytes memory bytecode = type(PegTokenBeaconProxy).creationCode;
        bytes32 salt = bytes32(bytes20(fromToken));
        // deploy new contract and store contract address in result variable
        address result;
        assembly {
            result := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
        }
        require(result != address(0x00), "beacon proxy deploy failed");
        // setup meta data
        (bool success,) = result.call(abi.encodeWithSelector(PegTokenBeaconProxy.initialize.selector, _originalThis));
        require(success, "erc20 proxy init failed");
        (success,) = result.call(abi.encodeWithSelector(ERC20PegToken.initialize.selector, metaData.symbol, metaData.name, fromChain, metaData.origin));
        require(success, "erc20 peg-token init failed");
        // return generated contract address
        return result;
    }

    function implementation() external view override returns (address) {
        return _tokenTemplate;
    }
}