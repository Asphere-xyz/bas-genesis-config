// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "../StakingConfig.sol";

contract StakingConfigUnsafe is InjectorContextHolder, AbstractStakingConfig {

    constructor(ConstructorArguments memory constructorArgs) InjectorContextHolder(constructorArgs) AbstractStakingConfig(address(0x0000000000000000000000000000000000000000)) {
    }

    function initialize(
        uint32 activeValidatorsLength,
        uint32 epochBlockInterval,
        uint32 misdemeanorThreshold,
        uint32 felonyThreshold,
        uint32 validatorJailEpochLength,
        uint32 undelegatePeriod,
        uint256 minValidatorStakeAmount,
        uint256 minStakingAmount,
        uint16 finalityRewardRatio
    ) external initializer {
        _slot0.activeValidatorsLength = activeValidatorsLength;
        emit ActiveValidatorsLengthChanged(0, activeValidatorsLength);
        _slot0.epochBlockInterval = epochBlockInterval;
        emit EpochBlockIntervalChanged(0, epochBlockInterval);
        _slot0.misdemeanorThreshold = misdemeanorThreshold;
        emit MisdemeanorThresholdChanged(0, misdemeanorThreshold);
        _slot0.felonyThreshold = felonyThreshold;
        emit FelonyThresholdChanged(0, felonyThreshold);
        _slot0.validatorJailEpochLength = validatorJailEpochLength;
        emit ValidatorJailEpochLengthChanged(0, validatorJailEpochLength);
        _slot0.undelegatePeriod = undelegatePeriod;
        emit UndelegatePeriodChanged(0, undelegatePeriod);
        _slot0.minValidatorStakeAmount = minValidatorStakeAmount;
        emit MinValidatorStakeAmountChanged(0, minValidatorStakeAmount);
        _slot0.minStakingAmount = minStakingAmount;
        emit MinStakingAmountChanged(0, minStakingAmount);
        _slot0.finalityRewardRatio = finalityRewardRatio;
        emit FinalityRewardRatioChanged(0, finalityRewardRatio);
    }
}