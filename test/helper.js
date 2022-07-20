/** @var web3 {Web3} */
const BigNumber = require("bignumber.js");
const {keccak256, toChecksumAddress} = require('ethereumjs-util');
const AbiCoder = require('web3-eth-abi');
const RLP = require('rlp');

const IStakingConfig = artifacts.require('IStakingConfig')
const IStaking = artifacts.require('IStaking')
const ISlashingIndicator = artifacts.require('ISlashingIndicator')
const ISystemReward = artifacts.require('ISystemReward')
const IGovernance = artifacts.require('IGovernance')
const IStakingPool = artifacts.require('IStakingPool')
const IRuntimeUpgrade = artifacts.require('IRuntimeUpgrade')
const IDeployerProxy = artifacts.require('IDeployerProxy')
const IRelayHub = artifacts.require('IRelayHub')
const ICrossChainBridge = artifacts.require('ICrossChainBridge')

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
  finalityRewardRatio: '1000', // 10%
  rootDefaultVerificationFunction: '0x0000000000000000000000000000000000000000',
  childDefaultVerificationFunction: '0x0000000000000000000000000000000000000000',
  nativeTokenSymbol: 'BAS',
  nativeTokenName: 'BAS',
};

const DEFAULT_CONTRACT_TYPES = {
  StakingConfig: artifacts.require('StakingConfig'),
  Staking: artifacts.require('Staking'),
  SlashingIndicator: artifacts.require('SlashingIndicator'),
  SystemReward: artifacts.require('SystemReward'),
  Governance: artifacts.require('Governance'),
  StakingPool: artifacts.require('StakingPool'),
  RuntimeUpgrade: artifacts.require('RuntimeUpgrade'),
  DeployerProxy: artifacts.require('DeployerProxy'),
  RelayHub: artifacts.require('RelayHub'),
  CrossChainBridge: artifacts.require('CrossChainBridge'),
  RuntimeProxy: artifacts.require('RuntimeProxy'),
  InjectorContextHolder: artifacts.require('InjectorContextHolder'),
};

const MOCK_CONTRACT_TYPES = {
  StakingConfig: artifacts.require('StakingConfigUnsafe'),
  Staking: artifacts.require('StakingUnsafe'),
  SlashingIndicator: artifacts.require('SlashingIndicatorUnsafe'),
  SystemReward: artifacts.require('SystemRewardUnsafe'),
  Governance: artifacts.require('GovernanceUnsafe'),
  StakingPool: artifacts.require('StakingPoolUnsafe'),
  RuntimeUpgrade: artifacts.require('RuntimeUpgradeUnsafe'),
  DeployerProxy: artifacts.require('DeployerProxyUnsafe'),
  RelayHub: artifacts.require('TestRelayHub'),
  CrossChainBridge: artifacts.require('TestCrossChainBridge'),
};

const newContractUsingTypes = async (owner, params, types = {}) => {
  const {
    StakingConfig,
    Staking,
    SlashingIndicator,
    SystemReward,
    Governance,
    StakingPool,
    RuntimeUpgrade,
    DeployerProxy,
    RelayHub,
    CrossChainBridge,
    RuntimeProxy,
    InjectorContextHolder,
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
    finalityRewardRatio,
    rootDefaultVerificationFunction,
    childDefaultVerificationFunction,
    nativeTokenSymbol,
    nativeTokenName,
  } = Object.assign({}, DEFAULT_MOCK_PARAMS, params)
  // convert single param to the object
  if (typeof systemTreasury === 'string') {
    systemTreasury = {[systemTreasury]: '10000'}
  }
  // precompute system contract addresses
  const latestNonce = await web3.eth.getTransactionCount(owner, 'pending')
  const systemAddresses = []
  for (let i = 0; i < 10; i++) {
    const nonceHash = keccak256(RLP.encode([owner, latestNonce + i])).toString('hex');
    systemAddresses.push(toChecksumAddress(`0x${nonceHash.substring(24)}`));
  }
  const runtimeUpgradeAddress = systemAddresses[6];
  // encode constructor for injector
  const injectorArgs = AbiCoder.encodeParameters(systemAddresses.map(() => 'address'), systemAddresses)
  const encodeInitializer = (types, args) => {
    const sig = keccak256(Buffer.from('initialize(' + types.join(',') + ')')).toString('hex').substring(0, 8),
      abi = AbiCoder.encodeParameters(types, args).substring(2)
    return `0x${sig}${abi}`
  }
  const newRuntimeProxy = async (contractType, initializerInput) => {
    const contractBytecode = contractType.bytecode + injectorArgs.substr(2)
    const json = contractType.toJSON(),
      [{inputs}] = json.abi.filter(({name}) => name === 'initialize')
    if (!inputs) throw new Error(`Can't resolve "initialize" function in the smart contract ${contractType.name}`)
    return await RuntimeProxy.new(runtimeUpgradeAddress, contractBytecode, encodeInitializer(inputs.map(({type}) => type), initializerInput), {from: owner});
  }
  // factory system contracts
  const staking = await newRuntimeProxy(Staking, [genesisValidators, genesisValidators.map(() => '0x'), genesisValidators, genesisValidators.map(() => '0'), '0']);
  const slashingIndicator = await newRuntimeProxy(SlashingIndicator, []);
  const systemReward = await newRuntimeProxy(SystemReward, [Object.keys(systemTreasury), Object.values(systemTreasury)]);
  const stakingPool = await newRuntimeProxy(StakingPool, []);
  const governance = await newRuntimeProxy(Governance, [votingPeriod, 'Governance']);
  const stakingConfig = await newRuntimeProxy(StakingConfig, [activeValidatorsLength, epochBlockInterval, misdemeanorThreshold, felonyThreshold, validatorJailEpochLength, undelegatePeriod, minValidatorStakeAmount, minStakingAmount, finalityRewardRatio]);
  const runtimeUpgrade = await RuntimeUpgrade.new(systemAddresses, {from: owner});
  const deployerProxy = await newRuntimeProxy(DeployerProxy, [genesisDeployers]);
  const relayHub = await newRuntimeProxy(RelayHub, [rootDefaultVerificationFunction, childDefaultVerificationFunction]);
  const crossChainBridge = await newRuntimeProxy(CrossChainBridge, [relayHub.address, nativeTokenSymbol, nativeTokenName]);
  // make sure runtime upgrade address is correct
  if (runtimeUpgrade.address.toLowerCase() !== runtimeUpgradeAddress.toLowerCase()) {
    console.log(`Required system address order: ${JSON.stringify(systemAddresses, null, 2)}`)
    console.log(`Produced system address order: ${JSON.stringify([
      staking.address,
      slashingIndicator.address,
      systemReward.address,
      stakingPool.address,
      governance.address,
      stakingConfig.address,
      runtimeUpgrade.address,
      deployerProxy.address,
      relayHub.address,
      crossChainBridge.address,
    ], null, 2)}`);
    throw new Error(`Runtime upgrade position mismatched, its not allowed (${runtimeUpgrade.address} != ${runtimeUpgradeAddress})`)
  }
  // run consensus init
  await runtimeUpgrade.init({from: owner});
  await (await InjectorContextHolder.at(staking.address)).init();
  await (await InjectorContextHolder.at(slashingIndicator.address)).init({from: owner});
  await (await InjectorContextHolder.at(systemReward.address)).init({from: owner});
  await (await InjectorContextHolder.at(stakingPool.address)).init({from: owner});
  await (await InjectorContextHolder.at(governance.address)).init({from: owner});
  await (await InjectorContextHolder.at(stakingConfig.address)).init({from: owner});
  await (await InjectorContextHolder.at(deployerProxy.address)).init({from: owner});
  await (await InjectorContextHolder.at(relayHub.address)).init({from: owner});
  await (await InjectorContextHolder.at(crossChainBridge.address)).init({from: owner});
  // patch staking interface to be compatible with unit tests
  const stakingConfig2 = await StakingConfig.at(stakingConfig.address);
  IStaking.prototype.getEpochBlockInterval = async () => {
    return stakingConfig2.getEpochBlockInterval()
  }
  // map proxies to the correct ABIs
  return {
    staking: await IStaking.at(staking.address),
    parlia: await IStaking.at(staking.address),
    slashingIndicator: await SlashingIndicator.at(slashingIndicator.address),
    systemReward: await SystemReward.at(systemReward.address),
    stakingPool: await StakingPool.at(stakingPool.address),
    governance: await Governance.at(governance.address),
    stakingConfig: await StakingConfig.at(stakingConfig.address),
    config: await StakingConfig.at(stakingConfig.address),
    runtimeUpgrade,
    deployer: await DeployerProxy.at(deployerProxy.address),
    deployerProxy: await DeployerProxy.at(deployerProxy.address),
    relayHub: await RelayHub.at(relayHub.address),
    crossChainBridge: await CrossChainBridge.at(crossChainBridge.address),
  }
}

const newMockContract = async (owner, params = {}) => {
  return newContractUsingTypes(owner, params, MOCK_CONTRACT_TYPES);
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
  let promises = []
  for (let i = 0; i < count; i++) {
    promises.push(advanceBlock());
  }
  await Promise.all(promises)
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

let totalAwaitTime = 0;

const waitForNextEpoch = async (parlia) => {
  let elapsedTime = new Date().getTime()
  const epochBlockInterval = Number(await parlia.getEpochBlockInterval()),
    currentBlockNumber = Number(await web3.eth.getBlockNumber())
  const nextEpochAt = ((currentBlockNumber / epochBlockInterval) | 0) * epochBlockInterval + epochBlockInterval,
    mineBlocks = nextEpochAt - currentBlockNumber
  await advanceBlocks(mineBlocks);
  elapsedTime = new Date().getTime() - elapsedTime
  totalAwaitTime += elapsedTime
}

module.exports = {
  newMockContract,
  expectError,
  extractTxCost,
  waitForNextEpoch,
  advanceBlock,
  advanceBlocks,
}