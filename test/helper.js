/** @var web3 {Web3} */
const BigNumber = require("bignumber.js");

const ChainConfig = artifacts.require("ChainConfig");
const Staking = artifacts.require("Staking");
const SlashingIndicator = artifacts.require("SlashingIndicator");
const SystemReward = artifacts.require("SystemReward");
const Governance = artifacts.require("Governance");
const StakingPool = artifacts.require("StakingPool");
const FakeStaking = artifacts.require("FakeStaking");

const DEFAULT_MOCK_PARAMS = {
  systemTreasury: '0x0000000000000000000000000000000000000000',
  activeValidatorsLength: '3',
  epochBlockInterval: '10',
  misdemeanorThreshold: '50',
  felonyThreshold: '150',
  validatorJailEpochLength: '7',
  undelegatePeriod: '0',
  minValidatorStakeAmount: '1',
  minStakingAmount: '1',
  genesisValidators: [],
};

const DEFAULT_CONTRACT_TYPES = {
  ChainConfig: ChainConfig,
  Staking: Staking,
  SlashingIndicator: SlashingIndicator,
  SystemReward: SystemReward,
  Governance: Governance,
  StakingPool: StakingPool,
};

const newContractUsingTypes = async (owner, params, types = {}) => {
  const {
    ChainConfig,
    Staking,
    SlashingIndicator,
    SystemReward,
    Governance,
    StakingPool,
  } = Object.assign({}, DEFAULT_CONTRACT_TYPES, types)
  const {
    systemTreasury,
    activeValidatorsLength,
    epochBlockInterval,
    misdemeanorThreshold,
    felonyThreshold,
    validatorJailEpochLength,
    genesisValidators,
    undelegatePeriod,
    minValidatorStakeAmount,
    minStakingAmount,
  } = Object.assign({}, DEFAULT_MOCK_PARAMS, params)
  // factory contracts
  const staking = await Staking.new(genesisValidators, '0', '0');
  const slashingIndicator = await SlashingIndicator.new();
  const systemReward = await SystemReward.new(systemTreasury);
  const governance = await Governance.new(1);
  const chainConfig = await ChainConfig.new(activeValidatorsLength, epochBlockInterval, misdemeanorThreshold, felonyThreshold, validatorJailEpochLength, undelegatePeriod, minValidatorStakeAmount, minStakingAmount);
  const stakingPool = await StakingPool.new();
  // init them all
  for (const contract of [chainConfig, staking, slashingIndicator, systemReward, stakingPool, governance]) {
    await contract.initManually(
      staking.address,
      slashingIndicator.address,
      systemReward.address,
      stakingPool.address,
      governance.address,
      chainConfig.address,
    );
  }
  return {
    staking,
    parlia: staking,
    slashingIndicator,
    systemReward,
    stakingPool,
    governance,
    chainConfig,
    config: chainConfig,
  }
}

const newMockContract = async (owner, params = {}) => {
  return newContractUsingTypes(owner, params, {
    Staking: FakeStaking,
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
  newMockContract,
  expectError,
  extractTxCost,
  waitForNextEpoch,
  advanceBlock,
  advanceBlocks,
}