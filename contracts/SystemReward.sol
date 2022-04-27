// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "./Injector.sol";

contract SystemReward is ISystemReward, InjectorContextHolder {

    /**
     * Parlia has 100 ether limit for max fee, its better to enable auto claim
     * for the system treasury otherwise it might cause lost of funds
     */
    uint256 public constant TREASURY_AUTO_CLAIM_THRESHOLD = 50 ether;
    uint256 public constant TREASURY_MIN_CLAIM_THRESHOLD = 10 wei;
    /**
     * Here is min/max share values.
     *
     * Here is some examples:
     * + 0.3% => 0.3*100=30
     * + 3% => 3*100=300
     * + 30% => 30*100=3000
     */
    uint16 internal constant SHARE_MIN_VALUE = 0; // 0%
    uint16 internal constant SHARE_MAX_VALUE = 10000; // 100%

    event DistributionShareChanged(address account, uint16 share);
    event FeeClaimed(address account, uint256 amount);

    // total system fee that is available for claim for system needs
    address internal _systemTreasury;
    uint256 internal _systemFee;

    struct DistributionShare {
        address account;
        uint16 share;
    }

    // distribution share between holders
    DistributionShare[] internal _distributionShares;

    constructor(bytes memory constructorParams) InjectorContextHolder(constructorParams) {
    }

    function ctor(address[] calldata accounts, uint16[] calldata shares) external whenNotInitialized {
        _updateDistributionShare(accounts, shares);
    }

    function getDistributionShares() external view returns (DistributionShare[] memory) {
        return _distributionShares;
    }

    function _updateDistributionShare(address[] calldata accounts, uint16[] calldata shares) internal {
        require(accounts.length == shares.length, "SystemReward: bad length");
        // force claim system fee before changing distribution share
        _claimSystemFee();
        uint16 totalShares = 0;
        for (uint256 i = 0; i < accounts.length; i++) {
            address account = accounts[i];
            uint16 share = shares[i];
            require(share >= SHARE_MIN_VALUE && share <= SHARE_MAX_VALUE, "SystemReward: bad share distribution");
            if (i >= _distributionShares.length) {
                _distributionShares.push(DistributionShare(account, share));
            } else {
                _distributionShares[i] = DistributionShare(account, share);
            }
            emit DistributionShareChanged(account, share);
            totalShares += share;
        }
        require(totalShares == SHARE_MAX_VALUE, "SystemReward: bad share distribution");
        assembly {
            sstore(_distributionShares.slot, accounts.length)
        }
    }

    function updateDistributionShare(address[] calldata accounts, uint16[] calldata shares) external virtual override onlyFromGovernance {
        _updateDistributionShare(accounts, shares);
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
        uint256 amountToPay = _systemFee;
        if (amountToPay <= TREASURY_MIN_CLAIM_THRESHOLD) {
            return;
        }
        _systemFee = 0;
        // if we have system treasury then its legacy scheme
        if (_systemTreasury != address(0x00)) {
            address payable payableTreasury = payable(_systemTreasury);
            payableTreasury.transfer(amountToPay);
            emit FeeClaimed(_systemTreasury, amountToPay);
            return;
        }
        // distribute rewards based on the shares
        uint256 totalPaid = 0;
        for (uint256 i = 0; i < _distributionShares.length; i++) {
            DistributionShare memory ds = _distributionShares[i];
            uint256 accountFee = amountToPay * ds.share / SHARE_MAX_VALUE;
            payable(ds.account).transfer(accountFee);
            emit FeeClaimed(ds.account, accountFee);
            totalPaid += accountFee;
        }
        // return some dust back to the acc
        _systemFee = amountToPay - totalPaid;
    }
}