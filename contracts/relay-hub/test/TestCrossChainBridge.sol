// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "../handler/FakeTokenHandler.sol";

import "../CrossChainBridge.sol";

contract TestCrossChainBridge is CrossChainBridge {

    constructor(ConstructorArguments memory constructorArgs) CrossChainBridge(constructorArgs) {
    }

    function _factoryTokenHandlers() internal override returns (IBridgeHandler erc20TokenHandler) {
        return (new FakeTokenHandler());
    }

    function getErc20TokenHandler() external view returns (address) {
        return (address(_erc20TokenHandler));
    }

    function _checkContractAllowed(ReceiptParser.State memory state) internal view override {
        // don't do this check for test because we don't have bridge address list
    }

    function factoryPeggedToken(uint256 fromChain, MetaData calldata metaData) external {
        // make sure this chain is supported
        require(_RELAY_HUB_CONTRACT.getBridgeAddress(fromChain) != address(0x00), "bad contract");
        // calc target token
        address toToken = _erc20TokenHandler.calcPegTokenAddress(address(this), metaData.origin);
        require(_peggedTokenOrigin[toToken] == address(0x00), "already exists");
        // deploy new token (its just a warmup operation)
        _factoryPeggedToken(toToken, metaData, fromChain);
    }

    function getRelayHub() external view returns (IRelayHub) {
        return _RELAY_HUB_CONTRACT;
    }

    modifier onlyFromCoinbase() override {
        _;
    }

    modifier onlyFromGovernance() override {
        _;
    }

    modifier onlyBlock(uint64 /*blockNumber*/) override {
        _;
    }
}