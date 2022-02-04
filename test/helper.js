/** @var web3 {Web3} */

const Deployer = artifacts.require("Deployer");
const Governance = artifacts.require("Governance");
const Parlia = artifacts.require("Parlia");
const FakeStaking = artifacts.require("FakeStaking");

const newGovernanceContract = async (owner) => {
  const deployer = await Deployer.new([]);
  const governance = await Governance.new(owner, 1);
  const parlia = await Parlia.new([]);
  await deployer.initManually(deployer.address, governance.address, parlia.address);
  await governance.initManually(deployer.address, governance.address, parlia.address);
  await parlia.initManually(deployer.address, governance.address, parlia.address);
  return {deployer, governance, parlia}
}

const newMockContract = async (owner) => {
  const deployer = await Deployer.new([]);
  const governance = await Governance.new(owner, 1);
  const parlia = await FakeStaking.new();
  await deployer.initManually(deployer.address, governance.address, parlia.address);
  await governance.initManually(deployer.address, governance.address, parlia.address);
  await parlia.initManually(deployer.address, governance.address, parlia.address);
  return {deployer, governance, parlia}
}

const createAndExecuteInstantProposal = async (
  // contracts
  governance,
  // proposal
  targets,
  values,
  calldatas,
  desc,
  // sender
  sender,
) => {
  const currentOwner = await governance.getOwner()
  if (currentOwner === '0x0000000000000000000000000000000000000000') await governance.obtainOwnership();
  const votingPower = await governance.getVotingPower(sender)
  if (votingPower.toString() === '0') await governance.setVotingPower(sender, '1000', {from: sender})
  const {logs: [{args: {proposalId}}]} = await governance.propose(targets, values, calldatas, desc, {from: sender})
  await governance.castVote(proposalId, 1, {from: sender})
  return await governance.execute(targets, values, calldatas, web3.utils.keccak256(desc), {from: sender},);
}

const randomProposalDesc = () => {
  return `${(Math.random() * 10000) | 0}`
}

const addValidator = async (governance, parlia, user, sender) => {
  const abi = parlia.contract.methods.addValidator(user).encodeABI()
  return createAndExecuteInstantProposal(governance, [parlia.address], ['0x00'], [abi], `Add ${user} validator (${randomProposalDesc()})`, sender)
}

const removeValidator = async (governance, parlia, user, sender) => {
  const abi = parlia.contract.methods.removeValidator(user).encodeABI()
  return createAndExecuteInstantProposal(governance, [parlia.address], ['0x00'], [abi], `Remove ${user} validator (${randomProposalDesc()})`, sender)
}

const addDeployer = async (governance, deployer, user, sender) => {
  const abi = deployer.contract.methods.addDeployer(user).encodeABI()
  return createAndExecuteInstantProposal(governance, [deployer.address], ['0x00'], [abi], `Add ${user} deployer (${randomProposalDesc()})`, sender)
}

const removeDeployer = async (governance, deployer, user, sender) => {
  const abi = deployer.contract.methods.removeDeployer(user).encodeABI()
  return createAndExecuteInstantProposal(governance, [deployer.address], ['0x00'], [abi], `Remove ${user} deployer (${randomProposalDesc()})`, sender)
}

const registerDeployedContract = async (governance, deployer, owner, contract, sender) => {
  const abi = deployer.contract.methods.registerDeployedContract(owner, contract).encodeABI();
  return createAndExecuteInstantProposal(governance, [deployer.address], ['0x00'], [abi], `Register ${contract} deployed contract (${randomProposalDesc()})`, sender)
}

module.exports = {
  newGovernanceContract,
  newMockContract,
  addValidator,
  removeValidator,
  addDeployer,
  removeDeployer,
  registerDeployedContract,
  createAndExecuteInstantProposal,
}