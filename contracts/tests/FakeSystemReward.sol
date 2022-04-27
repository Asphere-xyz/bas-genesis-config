// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "../SystemReward.sol";

contract FakeSystemReward is SystemReward {

    constructor(bytes memory constructorParams) SystemReward(constructorParams) {
    }

    function updateDistributionShare(address[] calldata accounts, uint16[] calldata shares) external virtual override {
        _updateDistributionShare(accounts, shares);
    }
}