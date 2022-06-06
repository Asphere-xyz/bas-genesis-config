/** @var web3 {Web3} */
const BigNumber = require("bignumber.js");
const {keccak256, toChecksumAddress} = require('ethereumjs-util');
const AbiCoder = require('web3-eth-abi');
const RLP = require('rlp');

const InjectorContextHolder = artifacts.require("InjectorContextHolder");
const ChainConfig = artifacts.require("ChainConfig");
const Staking = artifacts.require("Staking");
const SlashingIndicator = artifacts.require("SlashingIndicator");
const SystemReward = artifacts.require("SystemReward");
const Governance = artifacts.require("Governance");
const StakingPool = artifacts.require("StakingPool");
const RuntimeUpgrade = artifacts.require("RuntimeUpgrade");
const RuntimeProxy = artifacts.require("RuntimeProxy");
const DeployerProxy = artifacts.require("DeployerProxy");

const FakeChainConfig = artifacts.require("FakeChainConfig");
const FakeDeployerProxy = artifacts.require("FakeDeployerProxy");
const FakeGovernance = artifacts.require("FakeGovernance");
const FakeRuntimeUpgrade = artifacts.require("FakeRuntimeUpgrade");
const FakeSlashingIndicator = artifacts.require("FakeSlashingIndicator");
const FakeStaking = artifacts.require("FakeStaking");
const FakeStakingPool = artifacts.require("FakeStakingPool");
const FakeSystemReward = artifacts.require("FakeSystemReward");

const DEFAULT_MOCK_PARAMS = {
  systemTreasury: '0x0000000000000000000000000000000000000000',
  activeValidatorsLength: '3',
  epochBlockInterval: '10',
  misdemeanorThreshold: '50',
  felonyThreshold: '150',
  validatorJailEpochLength: '7',
  undelegatePeriod: '0',
  minValidatorStakeAmount: '1000000000000000000',
  minStakingAmount: '1000000000000000000',
  genesisValidators: [],
  genesisDeployers: [],
  votingPeriod: '2',
};

const DEFAULT_CONTRACT_TYPES = {
  ChainConfig: ChainConfig,
  Staking: Staking,
  SlashingIndicator: SlashingIndicator,
  SystemReward: SystemReward,
  Governance: Governance,
  StakingPool: StakingPool,
  RuntimeUpgrade: RuntimeUpgrade,
  DeployerProxy: DeployerProxy,
};

const encodeABI = (types, args) => {
  const sig = keccak256(Buffer.from('initialize(' + types.join(',') + ')')).toString('hex').substring(0, 8),
    abi = AbiCoder.encodeParameters(types, args).substring(2)
  return `0x${sig}${abi}`
}

const newContractUsingTypes = async (owner, params, types = {}) => {
  const {
    ChainConfig,
    Staking,
    SlashingIndicator,
    SystemReward,
    Governance,
    StakingPool,
    RuntimeUpgrade,
    DeployerProxy,
  } = Object.assign({}, DEFAULT_CONTRACT_TYPES, types)
  let {
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
    votingPeriod,
    genesisDeployers,
  } = Object.assign({}, DEFAULT_MOCK_PARAMS, params)
  // convert single param to the object
  if (typeof systemTreasury === 'string') {
    systemTreasury = {[systemTreasury]: '10000'}
  }
  // precompute system contract addresses
  const latestNonce = await web3.eth.getTransactionCount(owner, 'pending')
  const systemAddresses = []
  for (let i = 0; i < 8; i++) {
    const nonceHash = keccak256(RLP.encode([owner, latestNonce + i])).toString('hex');
    systemAddresses.push(toChecksumAddress(`0x${nonceHash.substring(24)}`));
  }
  const runtimeUpgradeAddress = systemAddresses[6];
  // encode constructor for injector
  const injectorArgs = AbiCoder.encodeParameters(['address', 'address', 'address', 'address', 'address', 'address', 'address', 'address',], systemAddresses)
  const injectorBytecode = ({bytecode}) => {
    return bytecode + injectorArgs.substr(2)
  }
  // factory system contracts
  const staking = await RuntimeProxy.new(runtimeUpgradeAddress, injectorBytecode(Staking), encodeABI(['address[]', 'address[]', 'uint256[]', 'uint16'], [genesisValidators, genesisValidators, genesisValidators.map(() => '0'), '0']), {from: owner});
  const slashingIndicator = await RuntimeProxy.new(runtimeUpgradeAddress, injectorBytecode(SlashingIndicator), encodeABI([], []), {from: owner});
  const systemReward = await RuntimeProxy.new(runtimeUpgradeAddress, injectorBytecode(SystemReward), encodeABI(['address[]', 'uint16[]'], [Object.keys(systemTreasury), Object.values(systemTreasury)]), {from: owner});
  const stakingPool = await RuntimeProxy.new(runtimeUpgradeAddress, injectorBytecode(StakingPool), encodeABI([], []), {from: owner});
  const governance = await RuntimeProxy.new(runtimeUpgradeAddress, injectorBytecode(Governance), encodeABI(['uint256', 'string'], [votingPeriod, 'Governance']), {from: owner});
  const chainConfig = await RuntimeProxy.new(runtimeUpgradeAddress, injectorBytecode(ChainConfig), encodeABI(['uint32', 'uint32', 'uint32', 'uint32', 'uint32', 'uint32', 'uint256', 'uint256'], [activeValidatorsLength, epochBlockInterval, misdemeanorThreshold, felonyThreshold, validatorJailEpochLength, undelegatePeriod, minValidatorStakeAmount, minStakingAmount]), {from: owner});
  const runtimeUpgrade = await RuntimeUpgrade.new(...systemAddresses, {from: owner});
  const deployerProxy = await RuntimeProxy.new(runtimeUpgradeAddress, injectorBytecode(DeployerProxy), encodeABI(['address[]'], [genesisDeployers]), {from: owner});
  // make sure runtime upgrade address is correct
  if (runtimeUpgrade.address.toLowerCase() !== runtimeUpgradeAddress.toLowerCase()) {
    console.log(`System addresses: ${JSON.stringify(systemAddresses, null, 2)}`)
    throw new Error(`Runtime upgrade position mismatched, its not allowed (${runtimeUpgrade.address} != ${runtimeUpgradeAddress})`)
  }
  // run consensus init
  await runtimeUpgrade.init({from: owner});
  await (await InjectorContextHolder.at(staking.address)).init();
  await (await InjectorContextHolder.at(slashingIndicator.address)).init({from: owner});
  await (await InjectorContextHolder.at(systemReward.address)).init({from: owner});
  await (await InjectorContextHolder.at(stakingPool.address)).init({from: owner});
  await (await InjectorContextHolder.at(governance.address)).init({from: owner});
  await (await InjectorContextHolder.at(chainConfig.address)).init({from: owner});
  await (await InjectorContextHolder.at(deployerProxy.address)).init({from: owner});
  // map proxies to the correct ABIs
  return {
    staking: await Staking.at(staking.address),
    parlia: await Staking.at(staking.address),
    slashingIndicator: await SlashingIndicator.at(slashingIndicator.address),
    systemReward: await SystemReward.at(systemReward.address),
    stakingPool: await StakingPool.at(stakingPool.address),
    governance: await Governance.at(governance.address),
    chainConfig: await ChainConfig.at(chainConfig.address),
    config: await ChainConfig.at(chainConfig.address),
    runtimeUpgrade,
    deployer: await DeployerProxy.at(deployerProxy.address),
    deployerProxy: await DeployerProxy.at(deployerProxy.address),
  }
}

const newMockContract = async (owner, params = {}) => {
  return newContractUsingTypes(owner, params, {
    ChainConfig: FakeChainConfig,
    DeployerProxy: FakeDeployerProxy,
    Governance: FakeGovernance,
    RuntimeUpgrade: FakeRuntimeUpgrade,
    SlashingIndicator: FakeSlashingIndicator,
    Staking: FakeStaking,
    StakingPool: FakeStakingPool,
    SystemReward: FakeSystemReward,
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
    if (e.message.includes(text) || !text) {
      return;
    }
    console.error(new Error(`Unexpected error: ${e.message}`))
  }
  console.error(new Error(`Expected error: ${text}`))
  assert.fail();
}

const extractTxCost = async (executionResult) => {
  let {receipt: {gasUsed, effectiveGasPrice}} = executionResult;
  if (typeof effectiveGasPrice === 'string') {
    effectiveGasPrice = new BigNumber(effectiveGasPrice.substring(2), 16)
  } else {
    effectiveGasPrice = new BigNumber(await web3.eth.getGasPrice(), 10)
  }
  executionResult.txCost = new BigNumber(gasUsed).multipliedBy(effectiveGasPrice);
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