// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorSettingsUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorCountingSimpleUpgradeable.sol";

import "./InjectorContextHolder.sol";

contract Governance is InjectorContextHolder, GovernorCountingSimpleUpgradeable, GovernorSettingsUpgradeable, IGovernance {

    uint256 internal _instantVotingPeriod;

    constructor(
        IStaking stakingContract,
        ISlashingIndicator slashingIndicatorContract,
        ISystemReward systemRewardContract,
        IStakingPool stakingPoolContract,
        IGovernance governanceContract,
        IChainConfig chainConfigContract,
        IRuntimeUpgrade runtimeUpgradeContract,
        IDeployerProxy deployerProxyContract
    ) InjectorContextHolder(
        stakingContract,
        slashingIndicatorContract,
        systemRewardContract,
        stakingPoolContract,
        governanceContract,
        chainConfigContract,
        runtimeUpgradeContract,
        deployerProxyContract
    ) {
    }

    function initialize(uint256 newVotingPeriod, string memory name) external initializer {
        __GovernorCountingSimple_init();
        __Governor_init(name);
        __GovernorSettings_init(0, newVotingPeriod, 0);
    }

    function getVotingSupply() external view returns (uint256) {
        return _votingSupply(block.number);
    }

    function getVotingPower(address validator) external view returns (uint256) {
        return _validatorOwnerVotingPowerAt(validator, block.number);
    }

    function proposeWithCustomVotingPeriod(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description,
        uint256 customVotingPeriod
    ) public virtual onlyValidatorOwner(msg.sender) returns (uint256) {
        _instantVotingPeriod = customVotingPeriod;
        uint256 proposalId = propose(targets, values, calldatas, description);
        _instantVotingPeriod = 0;
        return proposalId;
    }

    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) public virtual override onlyValidatorOwner(msg.sender) returns (uint256) {
        return GovernorUpgradeable.propose(targets, values, calldatas, description);
    }

    modifier onlyValidatorOwner(address account) {
        require(_validatorOwnerVotingPowerAt(account, block.number) > 0, "only owner with active validators");
        _;
    }

    function votingPeriod() public view override(IGovernorUpgradeable, GovernorSettingsUpgradeable) returns (uint256) {
        // let use re-defined voting period for the proposals
        if (_instantVotingPeriod != 0) {
            return _instantVotingPeriod;
        }
        return GovernorSettingsUpgradeable.votingPeriod();
    }

    function _getVotes(address account, uint256 blockNumber, bytes memory /*params*/) internal view virtual override returns (uint256) {
        return _validatorOwnerVotingPowerAt(account, blockNumber);
    }

    function _countVote(uint256 proposalId, address account, uint8 support, uint256 weight, bytes memory params) internal virtual override(GovernorUpgradeable, GovernorCountingSimpleUpgradeable) {
        uint256 deadline = proposalDeadline(proposalId);
        address[] memory validators = _STAKING_CONTRACT.getValidatorsByOwner(account);
        uint256 votingPower = 0;
        for (uint256 i = 0; i < validators.length; i++) {
            address validatorAddress = validators[i];
            uint256 validatorVotingPower = _validatorVotingPowerAt(validatorAddress, deadline);
            super._countVote(proposalId, validatorAddress, support, validatorVotingPower, params);
            votingPower += validatorVotingPower;
        }
        require(votingPower == weight, "corrupted weight");
    }

    function _validatorOwnerVotingPowerAt(address validatorOwner, uint256 blockNumber) internal view returns (uint256) {
        address[] memory validators = _STAKING_CONTRACT.getValidatorsByOwner(validatorOwner);
        uint256 votingPower = 0;
        for (uint256 i = 0; i < validators.length; i++) {
            votingPower += _validatorVotingPowerAt(validators[i], blockNumber);
        }
        return votingPower;
    }

    function _validatorVotingPowerAt(address validator, uint256 blockNumber) internal view returns (uint256) {
        // find validator votes at block number
        uint64 epoch = uint64(blockNumber / _CHAIN_CONFIG_CONTRACT.getEpochBlockInterval());
        (,uint8 status,uint256 totalDelegated,,,,,,) = _STAKING_CONTRACT.getValidatorStatusAtEpoch(validator, epoch);
        if (status != 0x01) {
            return 0;
        }
        // use total delegated amount is a voting power
        return totalDelegated;
    }

    function _votingSupply(uint256 blockNumber) internal view returns (uint256 votingSupply) {
        address[] memory validators = _STAKING_CONTRACT.getValidators();
        for (uint256 i = 0; i < validators.length; i++) {
            votingSupply += _validatorVotingPowerAt(validators[i], blockNumber);
        }
        return votingSupply;
    }

    function quorum(uint256 blockNumber) public view override returns (uint256) {
        uint256 votingSupply = _votingSupply(blockNumber);
        return votingSupply * 2 / 3;
    }

    function votingDelay() public view override(IGovernorUpgradeable, GovernorSettingsUpgradeable) returns (uint256) {
        return GovernorSettingsUpgradeable.votingDelay();
    }

    function proposalThreshold() public view virtual override(GovernorUpgradeable, GovernorSettingsUpgradeable) returns (uint256) {
        return GovernorSettingsUpgradeable.proposalThreshold();
    }
}