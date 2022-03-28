// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/governance/extensions/GovernorSettings.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";

import "./Injector.sol";

contract Governance is InjectorContextHolder, GovernorCountingSimple, GovernorSettings, IGovernance {

    uint256 internal _instantVotingPeriod;

    constructor(bytes memory ctor) InjectorContextHolder(ctor) Governor("Governance") GovernorSettings(0, 1, 0) {
    }

    function ctor(uint256 newVotingPeriod) external whenNotInitialized {
        _setVotingPeriod(newVotingPeriod);
    }

    function getVotingSupply() external view returns (uint256) {
        return _votingSupply(block.number);
    }

    function getVotingPower(address validator) external view returns (uint256) {
        return _validatorVotingPowerAt(validator, block.number);
    }

    function proposeWithCustomVotingPeriod(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description,
        uint256 customVotingPeriod
    ) public virtual onlyValidatorOwner returns (uint256) {
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
    ) public virtual override onlyValidatorOwner returns (uint256) {
        return Governor.propose(targets, values, calldatas, description);
    }

    modifier onlyValidatorOwner() {
        address validatorAddress = _stakingContract.getValidatorByOwner(msg.sender);
        require(_stakingContract.isValidatorActive(validatorAddress), "Governance: only validator owner");
        _;
    }

    function votingPeriod() public view override(IGovernor, GovernorSettings) returns (uint256) {
        // let us re-defined voting period for proposers
        if (_instantVotingPeriod != 0) {
            return _instantVotingPeriod;
        }
        return GovernorSettings.votingPeriod();
    }

    function getVotes(address account, uint256 blockNumber) public view override returns (uint256) {
        return _validatorVotingPowerAt(account, blockNumber);
    }

    function _validatorVotingPowerAt(address validatorOwner, uint256 blockNumber) internal view returns (uint256) {
        address validator = _stakingContract.getValidatorByOwner(validatorOwner);
        // only active validators can vote
        if (!_stakingContract.isValidatorActive(validator)) {
            return 0;
        }
        // find validator votes at block number
        uint64 epoch = uint64(blockNumber / _chainConfigContract.getEpochBlockInterval());
        (,,uint256 totalDelegated,,,,,,) = _stakingContract.getValidatorStatusAtEpoch(validator, epoch);
        // use total delegated amount is a voting power
        return totalDelegated;
    }

    function _votingSupply(uint256 blockNumber) internal view returns (uint256 votingSupply) {
        address[] memory validators = _stakingContract.getValidators();
        for (uint256 i = 0; i < validators.length; i++) {
            votingSupply += _validatorVotingPowerAt(validators[i], blockNumber);
        }
        return votingSupply;
    }

    function quorum(uint256 blockNumber) public view override returns (uint256) {
        uint256 votingSupply = _votingSupply(blockNumber);
        return votingSupply * 2 / 3;
    }

    function votingDelay() public view override(IGovernor, GovernorSettings) returns (uint256) {
        return GovernorSettings.votingDelay();
    }

    function proposalThreshold() public view virtual override(Governor, GovernorSettings) returns (uint256) {
        return GovernorSettings.proposalThreshold();
    }
}