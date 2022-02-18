/** @var web3 {Web3} */
const BigNumber = require("bignumber.js");

const Staking = artifacts.require("Staking");
const SlashingIndicator = artifacts.require("SlashingIndicator");
const SystemReward = artifacts.require("SystemReward");

const ContractDeployer = artifacts.require("ContractDeployer");
const Governance = artifacts.require("Governance");

const FakeContractDeployer = artifacts.require("FakeContractDeployer");
const FakeStaking = artifacts.require("FakeStaking");

const DEFAULT_MOCK_PARAMS = {
  systemTreasury: '0x0000000000000000000000000000000000000000',
  activeValidatorsLength: '3',
  epochBlockInterval: '10',
  misdemeanorThreshold: '50',
  felonyThreshold: '150',
  validatorJailEpochLength: '7',
  undelegatePeriod: '0',
  genesisDeployers: [],
  genesisValidators: [],
};

const DEFAULT_CONTRACT_TYPES = {
  Staking: Staking,
  SlashingIndicator: SlashingIndicator,
  SystemReward: SystemReward,
  ContractDeployer: ContractDeployer,
  Governance: Governance,
};

const newContractUsingTypes = async (owner, params, types = {}) => {
  const {
    Staking,
    SlashingIndicator,
    SystemReward,
    ContractDeployer,
    Governance
  } = Object.assign({}, DEFAULT_CONTRACT_TYPES, types)
  const {
    systemTreasury,
    activeValidatorsLength,
    epochBlockInterval,
    misdemeanorThreshold,
    felonyThreshold,
    validatorJailEpochLength,
    genesisDeployers,
    genesisValidators,
    undelegatePeriod,
  } = Object.assign({}, DEFAULT_MOCK_PARAMS, params)
  // factory contracts
  const staking = await Staking.new(genesisValidators, systemTreasury, activeValidatorsLength, epochBlockInterval, misdemeanorThreshold, felonyThreshold, validatorJailEpochLength, undelegatePeriod);
  const slashingIndicator = await SlashingIndicator.new();
  const systemReward = await SystemReward.new();
  const contractDeployer = await ContractDeployer.new(genesisDeployers);
  const governance = await Governance.new(owner, 1);
  // init them all
  for (const contract of [staking, slashingIndicator, systemReward, contractDeployer, governance]) {
    await contract.initManually(
      staking.address,
      slashingIndicator.address,
      systemReward.address,
      contractDeployer.address,
      governance.address,
    );
  }
  return {
    staking,
    parlia: staking,
    slashingIndicator,
    systemReward,
    contractDeployer,
    deployer: contractDeployer,
    governance
  }
}

const newGovernanceContract = async (owner, params = {}) => {
  return newContractUsingTypes(owner, params);
}

const newMockContract = async (owner, params = {}) => {
  return newContractUsingTypes(owner, params, {
    Staking: FakeStaking,
    ContractDeployer: FakeContractDeployer,
  });
}

const advanceBlock = () => {
  return new Promise((resolve, reject) => {
    web3.currentProvider.send({
      jsonrpc: "2.0",
      method: "evm_mine",
      id: new Date().getTime()
    }, (err, result) => {
      if (err) {
        return reject(err);
      }
      const newBlockHash = web3.eth.getBlock("latest").hash;

      return resolve(newBlockHash);
    });
  });
};

const advanceBlocks = async (count) => {
  for (let i = 0; i < count; i++) {
    await advanceBlock();
  }
}

let proposalIndex = 0;

const createAndExecuteInstantProposal = async (
  // contracts
  governance,
  // proposal
  targets,
  values,
  calldatas,
  // sender
  sender,
) => {
  const desc = `Proposal #${proposalIndex++}`;
  const currentOwner = await governance.getOwner()
  if (currentOwner === '0x0000000000000000000000000000000000000000') await governance.obtainOwnership();
  const votingPower = await governance.getVotingPower(sender)
  if (votingPower.toString() === '0') await governance.setVotingPower(sender, '1000', {from: sender})
  const {logs: [{args: {proposalId}}]} = await governance.propose(targets, values, calldatas, desc, {from: sender})
  await governance.castVote(proposalId, 1, {from: sender})
  return await governance.execute(targets, values, calldatas, web3.utils.keccak256(desc), {from: sender},);
}

const addValidator = async (governance, parlia, user, sender) => {
  return createAndExecuteInstantProposal(
    governance,
    [parlia.address],
    ['0x00'],
    [parlia.contract.methods.addValidator(user).encodeABI()],
    sender)
}

const removeValidator = async (governance, parlia, user, sender) => {
  return createAndExecuteInstantProposal(
    governance,
    [parlia.address],
    ['0x00'],
    [parlia.contract.methods.removeValidator(user).encodeABI()],
    sender)
}

const addDeployer = async (governance, deployer, user, sender) => {
  return createAndExecuteInstantProposal(
    governance,
    [deployer.address],
    ['0x00'],
    [deployer.contract.methods.addDeployer(user).encodeABI()],
    sender)
}

const removeDeployer = async (governance, deployer, user, sender) => {
  return createAndExecuteInstantProposal(
    governance,
    [deployer.address],
    ['0x00'],
    [deployer.contract.methods.removeDeployer(user).encodeABI()],
    sender)
}

const registerDeployedContract = async (governance, deployer, owner, contract, sender) => {
  return createAndExecuteInstantProposal(
    governance,
    [deployer.address],
    ['0x00'],
    [deployer.contract.methods.registerDeployedContract(owner, contract).encodeABI()],
    sender)
}

const expectError = async (promise, text) => {
  try {
    await promise;
  } catch (e) {
    if (e.message.includes(text)) {
      return;
    }
    console.error(new Error(`Unexpected error: ${e.message}`))
  }
  console.error(new Error(`Expected error: ${text}`))
  assert.fail();
}

const extractTxCost = (executionResult) => {
  let {receipt: {gasUsed, effectiveGasPrice}} = executionResult;
  if (typeof effectiveGasPrice === 'string') {
    effectiveGasPrice = effectiveGasPrice.substring(2)
  } else {
    effectiveGasPrice = '1' // for coverage
  }
  executionResult.txCost = new BigNumber(gasUsed).multipliedBy(new BigNumber(effectiveGasPrice, 16));
  return executionResult;
}

const waitForNextEpoch = async (parlia, blockStep = 1) => {
  const currentEpoch = await parlia.currentEpoch()
  while (true) {
    await advanceBlocks(blockStep)
    const nextEpoch = await parlia.currentEpoch()
    if (`${currentEpoch}` === `${nextEpoch}`) continue;
    break;
  }
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
  expectError,
  extractTxCost,
  waitForNextEpoch,
  advanceBlock,
  advanceBlocks,
}