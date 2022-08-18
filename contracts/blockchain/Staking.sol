// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "./interfaces/IStaking.sol";
import "../InjectorContextHolder.sol";
import "../staking/AbstractStaking.sol";

/**
 * You might ask why this library model is so overcomplicated... the answer is that we tried
 * to keep backward compatibility with existing storage layout when smart contract size become more than 24kB.
 *
 * Since this checks works only for deployed smart contracts (not constructors) then we can deploy several
 * smart contracts with more than 24kB size.
 */
contract Staking is InjectorContextHolder, AbstractStaking {

    constructor(
        ConstructorArguments memory constructorArgs
    )
    InjectorContextHolder(constructorArgs)
    AbstractStaking(_STAKING_CONFIG_CONTRACT, StakingParams(
            address(_GOVERNANCE_CONTRACT),
            address(_SLASHING_INDICATOR_CONTRACT),
            address(_SYSTEM_REWARD_CONTRACT)
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