// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "../RelayHub.sol";

import "../verifiers/FakeBlockVerifier.sol";

contract TestRelayHub is RelayHub {

    constructor() RelayHub(new FakeBlockVerifier(), ZERO_STAKING_ADDRESS) {
    }

    function enableCrossChainBridge(uint256 chainId, address bridgeAddress) external {
        _registeredChains[chainId].bridgeAddress = bridgeAddress;
        _registeredChains[chainId].chainStatus = ChainStatus.Active;
    }
}