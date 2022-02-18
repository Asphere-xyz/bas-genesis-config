// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "./Injector.sol";

contract SystemReward is ISystemReward, InjectorContextHolder {

    receive() external payable {
        // we need this proxy to be compatible with BSC
        payable(address(_stakingContract)).transfer(msg.value);
    }
}