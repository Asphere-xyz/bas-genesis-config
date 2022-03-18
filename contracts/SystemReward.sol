// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "./Injector.sol";

contract SystemReward is ISystemReward, InjectorContextHolder {

    /**
     * Parlia has 100 ether limit for max fee, its better to enable auto claim
     * for the system treasury otherwise it might cause lost of funds
     */
    uint256 public constant TREASURY_AUTO_CLAIM_THRESHOLD = 50 ether;

    // total system fee that is available for claim for system needs
    address internal _systemTreasury;
    uint256 internal _systemFee;

    constructor(bytes memory ctor) InjectorContextHolder(ctor) {
    }

    function ctor(address systemTreasury) external whenNotInitialized {
        _systemTreasury = systemTreasury;
    }

    function getSystemFee() external view override returns (uint256) {
        return _systemFee;
    }

    function claimSystemFee() external override {
        _claimSystemFee();
    }

    receive() external payable {
        // increase total system fee
        _systemFee += msg.value;
        // once max fee threshold is reached lets do force claim
        if (_systemFee >= TREASURY_AUTO_CLAIM_THRESHOLD) {
            _claimSystemFee();
        }
    }

    function _claimSystemFee() internal {
        address payable payableTreasury = payable(_systemTreasury);
        payableTreasury.transfer(_systemFee);
        _systemFee = 0;
    }
}