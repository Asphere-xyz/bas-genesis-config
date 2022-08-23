// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "../RelayHub.sol";

import "../verifiers/FakeBlockVerifier.sol";

contract TestRelayHub is RelayHub {

    constructor(ConstructorArguments memory constructorArgs) RelayHub(constructorArgs) {
    }

    function enableCrossChainBridge(uint256 chainId, address bridgeAddress) external {
        _registeredChains[chainId].bridgeAddress = bridgeAddress;
        _registeredChains[chainId].chainStatus = ChainStatus.Active;
    }

    function checkReceiptProof(
        uint256 /*chainId*/,
        bytes[] calldata /*blockProofs*/,
        bytes calldata /*rawReceipt*/,
        bytes calldata /*proofSiblings*/,
        bytes calldata /*proofPath*/
    ) external pure override returns (bool) {
        return true;
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