// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "../../InjectorContextHolder.sol";
import "../../staking/AbstractStaking.sol";

contract StakingUnsafe is InjectorContextHolder, AbstractStaking {

    address internal constant ZERO_ADDRESS = 0x0000000000000000000000000000000000000000;

    constructor(
        ConstructorArguments memory constructorArgs
    )
    InjectorContextHolder(constructorArgs)
    AbstractStaking(_STAKING_CONFIG_CONTRACT, StakingParams(
            address(ZERO_ADDRESS),
            address(ZERO_ADDRESS),
            address(ZERO_ADDRESS)
        )) {
    }

    function initialize(
        address[] calldata validators,
        bytes[] calldata votingKeys,
        address[] calldata owners,
        uint256[] calldata initialStakes,
        uint16 commissionRate
    ) external initializer {
        require(validators.length == owners.length && validators.length == initialStakes.length);
        uint256 totalStakes = 0;
        for (uint256 i = 0; i < validators.length; i++) {
            _addValidator(validators[i], votingKeys[i], owners[i], ValidatorStatus.Active, commissionRate, initialStakes[i], 0);
            totalStakes += initialStakes[i];
        }
        require(address(this).balance == totalStakes);
    }

    function deposit() external payable onlyFromCoinbase {
        // for backward compatibility with parlia consensus engine
        _STAKING_CONTRACT.distributeRewards(msg.sender, msg.value);
    }
}