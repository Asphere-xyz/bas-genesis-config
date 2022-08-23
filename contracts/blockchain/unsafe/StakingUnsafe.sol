// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "../../InjectorContextHolder.sol";
import "../../staking/AbstractStaking.sol";

contract StakingValidatorRegistryWithInjectorUnsafe is InjectorContextHolder, StakingValidatorRegistry {

    constructor(
        ConstructorArguments memory constructorArgs,
        StakingParams memory stakingParams
    ) InjectorContextHolder(constructorArgs) StakingValidatorRegistry(constructorArgs.chainConfigContract, stakingParams) {
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

contract StakingRewardDistributionWithInjectorUnsafe is InjectorContextHolder, StakingRewardDistribution {

    constructor(
        ConstructorArguments memory constructorArgs,
        StakingParams memory stakingParams
    ) InjectorContextHolder(constructorArgs) StakingRewardDistribution(constructorArgs.chainConfigContract, stakingParams) {
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

/**
 * You might ask why this library model is so overcomplicated... the answer is that we tried
 * to keep backward compatibility with existing storage layout when smart contract size become more than 24kB.
 *
 * Since this checks works only for deployed smart contracts (not constructors) then we can deploy several
 * smart contracts with more than 24kB size.
 */
contract StakingUnsafe is InjectorContextHolder, AbstractStaking {

    constructor(
        ConstructorArguments memory constructorArgs
    )
    InjectorContextHolder(constructorArgs)
    AbstractStaking(constructorArgs.chainConfigContract, StakingParams(
            address(0x0000000000000000000000000000000000000000),
            address(0x0000000000000000000000000000000000000000),
            address(0x0000000000000000000000000000000000000000)
        ),
        new StakingValidatorRegistryWithInjectorUnsafe(constructorArgs, StakingParams(address(0x0000000000000000000000000000000000000000), address(0x0000000000000000000000000000000000000000), address(0x0000000000000000000000000000000000000000))),
        new StakingRewardDistributionWithInjectorUnsafe(constructorArgs, StakingParams(address(0x0000000000000000000000000000000000000000), address(0x0000000000000000000000000000000000000000), address(0x0000000000000000000000000000000000000000)))
    ) {
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