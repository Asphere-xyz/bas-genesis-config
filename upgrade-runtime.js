const Web3 = require('web3'),
  fs = require('fs');
const AbiCoder = require("web3-eth-abi");

const ABI_STAKING = require('./build/contracts/Staking.json').abi;
const ABI_GOVERNANCE = require('./build/contracts/Governance.json').abi;
const ABI_RUNTIME_UPGRADE = require('./build/contracts/RuntimeUpgrade.json').abi;

const askFor = async (question) => {
  return new Promise(resolve => {
    const readline = require('readline');
    const rl = readline.createInterface({
      input: process.stdin,
      output: process.stdout
    });
    rl.question(question, (value) => {
      resolve(value);
      rl.close();
    });
  })
}

const STAKING_ADDRESS = '0x0000000000000000000000000000000000001000';
const SLASHING_INDICATOR_ADDRESS = '0x0000000000000000000000000000000000001001';
const SYSTEM_REWARD_ADDRESS = '0x0000000000000000000000000000000000001002';
const STAKING_POOL_ADDRESS = '0x0000000000000000000000000000000000007001';
const GOVERNANCE_ADDRESS = '0x0000000000000000000000000000000000007002';
const CHAIN_CONFIG_ADDRESS = '0x0000000000000000000000000000000000007003';
const RUNTIME_UPGRADE_ADDRESS = '0x0000000000000000000000000000000000007004';
const DEPLOYER_PROXY_ADDRESS = '0x0000000000000000000000000000000000007005';

const ALL_ADDRESSES = [
  STAKING_ADDRESS,
  SLASHING_INDICATOR_ADDRESS,
  SYSTEM_REWARD_ADDRESS,
  STAKING_POOL_ADDRESS,
  GOVERNANCE_ADDRESS,
  CHAIN_CONFIG_ADDRESS,
  RUNTIME_UPGRADE_ADDRESS,
  DEPLOYER_PROXY_ADDRESS,
];

const UPGRADABLE_ADDRESSES = ALL_ADDRESSES.filter(c => c !== RUNTIME_UPGRADE_ADDRESS);

const readByteCodeForAddress = (address) => {
  const artifactPaths = {
    [STAKING_ADDRESS]: './build/contracts/Staking.json',
    [SLASHING_INDICATOR_ADDRESS]: './build/contracts/SlashingIndicator.json',
    [SYSTEM_REWARD_ADDRESS]: './build/contracts/SystemReward.json',
    [STAKING_POOL_ADDRESS]: './build/contracts/StakingPool.json',
    [GOVERNANCE_ADDRESS]: './build/contracts/Governance.json',
    [CHAIN_CONFIG_ADDRESS]: './build/contracts/ChainConfig.json',
    [RUNTIME_UPGRADE_ADDRESS]: './build/contracts/RuntimeUpgrade.json',
    [DEPLOYER_PROXY_ADDRESS]: './build/contracts/DeployerProxy.json',
  }
  const filePath = artifactPaths[address]
  if (!filePath) throw new Error(`There is no artifact for the address: ${address}`)
  const {bytecode} = JSON.parse(fs.readFileSync(filePath, 'utf8'))
  return bytecode
}

const sleepFor = async ms => {
  return new Promise(resolve => setTimeout(resolve, ms))
}

const injectorBytecode = (bytecode) => {
  const injectorArgs = AbiCoder.encodeParameters(['address', 'address', 'address', 'address', 'address', 'address', 'address', 'address',], ALL_ADDRESSES)
  return bytecode + injectorArgs.substr(2)
}

const proposalStates = ['Pending', 'Active', 'Canceled', 'Defeated', 'Succeeded', 'Queued', 'Expired', 'Executed'];

(async () => {
  const rpcUrl = process.argv[2];
  if (!rpcUrl) {
    console.error(`Specify RPC url`)
    process.exit(1);
  }
  const isAuto = process.argv.some(val => val === '--auto')
  const web3 = new Web3(rpcUrl);
  const signTx = async (account, {to, data, value}) => {
    const nonce = await web3.eth.getTransactionCount(account.address),
      chainId = await web3.eth.getChainId()
    const txOpts = {
      from: account.address,
      gas: 2_000_000,
      gasPrice: 5e9,
      nonce: nonce,
      to: to,
      data: data,
      chainId: chainId,
      value,
    }
    await web3.eth.call(txOpts)
    return account.signTransaction(txOpts)
  }
  const staking = new web3.eth.Contract(ABI_STAKING, STAKING_ADDRESS);
  const governance = new web3.eth.Contract(ABI_GOVERNANCE, GOVERNANCE_ADDRESS);
  const runtimeUpgrade = new web3.eth.Contract(ABI_RUNTIME_UPGRADE, RUNTIME_UPGRADE_ADDRESS);
  // make sure we have enough private keys
  const keystoreKeys = {}
  const keystorePassword = fs.readFileSync('./password.txt', 'utf8')
  console.log(`Decrypting keystore`);
  for (const filePath of fs.readdirSync('./keystore', 'utf8')) {
    const [address] = filePath.match(/([\da-f]{40})/ig);
    console.log(` ~ decrypting account 0x${address}`);
    keystoreKeys[`0x${address}`.toLowerCase()] = web3.eth.accounts.decrypt(JSON.parse(fs.readFileSync(`./keystore/${filePath}`, 'utf8')), keystorePassword);
  }
  const activeValidatorSet = await staking.methods.getValidators().call();
  let feedAll = false,
    faucetAddress = null;
  const feedValidator = async (validatorAddress) => {
    if (!faucetAddress) faucetAddress = await askFor(`What's faucet address? `)
    const faucetKeystore = keystoreKeys[faucetAddress.toLowerCase()]
    if (!faucetKeystore) throw new Error(`There is no faucet address in the keystore folder`)
    const {rawTransaction, transactionHash} = await signTx(faucetKeystore, {
      to: validatorAddress,
      value: '1000000000000000000' // 1 ether
    });
    console.log(` ~ feeding validator (${validatorAddress}): ${transactionHash}`);
    await web3.eth.sendSignedTransaction(rawTransaction);
  }
  for (const validatorAddress of activeValidatorSet) {
    if (!keystoreKeys[validatorAddress.toLowerCase()]) {
      throw new Error(`Unable to find private key in keystore for address: ${validatorAddress}`)
    }
    const balance = await web3.eth.getBalance(validatorAddress)
    if (balance === '0') {
      if (feedAll) {
        await feedValidator(validatorAddress);
        continue;
      }
      const answer = await askFor(`Validator (${validatorAddress}) has lack of funds, would you like to feed it from faucet? (yes/no/all) `)
      if (answer === 'yes' || answer === 'all') {
        await feedValidator(validatorAddress);
        feedAll = answer === 'all';
      }
    }
  }
  const someValidator = keystoreKeys[activeValidatorSet[0].toLowerCase()]
  if (!someValidator) {
    throw new Error(`There is no validators in the network, its not possible`)
  }
  const upgradeSystemContractByteCode = async (contractAddress, defaultByteCode = []) => {
    if (!Array.isArray(contractAddress)) {
      contractAddress = [contractAddress]
    }
    if (!Array.isArray(defaultByteCode)) {
      defaultByteCode = [defaultByteCode]
    }
    const [addresses, values, calls] = contractAddress.reduce(([addresses, values, calls], address, i) => {
      const byteCode = defaultByteCode[i] || readByteCodeForAddress(address),
        call = runtimeUpgrade.methods.upgradeSystemSmartContract(address, injectorBytecode(byteCode), '0x').encodeABI()
      addresses.push(RUNTIME_UPGRADE_ADDRESS);
      values.push('0');
      calls.push(call);
      return [addresses, values, calls]
    }, [[], [], []]);
    let governanceCall;
    const desc = `Runtime upgrade for (${contractAddress.join(',')}, at ${new Date().toLocaleString()})`;
    for (const i in calls) {
      console.log(`Testing call... from=${GOVERNANCE_ADDRESS} to=${addresses[i]}`);
      try {
        await web3.eth.call({
          value: values[i],
          from: GOVERNANCE_ADDRESS,
          to: addresses[i],
          data: calls[i],
        });
      } catch (e) {
        const yesNo = await askFor(`It seems runtime upgrade might fail with error (${e.message}), would you like to continue? (yes/no) `);
        if (yesNo !== 'yes') return;
      }
    }
    governanceCall = governance.methods.proposeWithCustomVotingPeriod(addresses, values, calls, desc, '20').encodeABI()
    const {rawTransaction, transactionHash} = await signTx(someValidator, {
      to: GOVERNANCE_ADDRESS,
      data: governanceCall,
    });
    console.log(`Creating proposal: ${transactionHash}`);
    const proposeReceipt = await web3.eth.sendSignedTransaction(rawTransaction);
    const proposalId = proposeReceipt.logs[0].data.substring(0, 66)
    // let's vote for this proposal using all our validators
    console.log(`Waiting for the proposal become active`);
    while (true) {
      const state = await governance.methods.state(proposalId).call(),
        status = proposalStates[Number(state)];
      if (status === 'Active') {
        console.log(`Proposal is active, we can start voting process`);
        break;
      } else if (status !== 'Pending') {
        console.error(`Incorrect proposal status: ${status}`)
        return;
      }
      await sleepFor(1_000)
    }
    console.log(`Voting for the proposal (${proposalId}):`);
    for (const validatorAddress of activeValidatorSet) {
      const account = keystoreKeys[validatorAddress.toLowerCase()],
        castCall = governance.methods.castVote(proposalId, '1').encodeABI()
      const {rawTransaction, transactionHash} = await signTx(account, {
        to: GOVERNANCE_ADDRESS,
        data: castCall,
      })
      console.log(` ~ validator ${validatorAddress} is voting: ${transactionHash}`)
      await web3.eth.sendSignedTransaction(rawTransaction)
    }
    // now we can execute the proposal
    while (true) {
      const currentBlock = await web3.eth.getBlockNumber()
      const state = await governance.methods.state(proposalId).call(),
        status = proposalStates[Number(state)];
      const deadline = await governance.methods.proposalDeadline(proposalId).call();
      console.log(`Current proposal status is: ${status}, current block is: ${currentBlock} deadline is: ${deadline}, elapsed: ${deadline - currentBlock}`)
      switch (status) {
        case 'Pending':
        case 'Active': {
          break;
        }
        case 'Succeeded': {
          const executeCall = governance.methods.execute(addresses, values, calls, web3.utils.keccak256(desc)).encodeABI()
          try {
            const result = await web3.eth.call({
              from: someValidator.address,
              to: GOVERNANCE_ADDRESS,
              data: executeCall
            })
            console.log(`Execute result: ${result}`)
          } catch (e) {
            console.error(`Failed to calc result: ${e}`)
          }
          const {rawTransaction, transactionHash} = await signTx(someValidator, {
            to: GOVERNANCE_ADDRESS,
            data: executeCall,
          });
          console.log(`Executing proposal: ${transactionHash}`);
          await web3.eth.sendSignedTransaction(rawTransaction);
          break;
        }
        case 'Executed': {
          console.log(`Proposal was successfully executed`);
          return;
        }
        default: {
          console.error(`Incorrect proposal status, upgrade failed: ${status}, exiting`)
          return;
        }
      }
      await sleepFor(12_000)
    }
  }
  // upgrade EVM hooks to the EIP-1967
  const isEIP1967 = async () => {
    try {
      return await runtimeUpgrade.methods.isEIP1967().call();
    } catch (e) {
      console.error(e)
    }
    return false;
  }
  const isNewRuntimeUpgrade = await isEIP1967();
  console.log(`isEIP1967: ${isNewRuntimeUpgrade}`);
  if (!isNewRuntimeUpgrade) {
    const existingRuntimeUpgradeCode = await web3.eth.getCode(RUNTIME_UPGRADE_ADDRESS)
    const yesOrNo = await askFor('It seems you\'re running EVM hook BAS version, it must be upgraded to the latest? (yes/no) ')
    if (yesOrNo !== 'yes') return;
    const runtimeUpgradeConstructor = injectorBytecode(readByteCodeForAddress(RUNTIME_UPGRADE_ADDRESS))
    const runtimeUpgradeBytecode = await web3.eth.call({
      data: runtimeUpgradeConstructor,
    });
    await upgradeSystemContractByteCode(RUNTIME_UPGRADE_ADDRESS, runtimeUpgradeBytecode);
    console.log(`Runtime upgrade is upgraded, now you can re-run this command to upgrade smart contracts to the latest version.`);
    process.exit(0);
  }
  // create new runtime upgrade proposal
  let contractAddress;
  if (isAuto) {
    contractAddress = 'auto'
  } else {
    contractAddress = await askFor('What address you\'d like to upgrade? (use "auto" for auto mode) ')
  }
  if (contractAddress === 'auto') {
    console.log(`Upgrading smart contract(s): ${UPGRADABLE_ADDRESSES}`);
    console.log(`---------------------------`);
    await upgradeSystemContractByteCode(UPGRADABLE_ADDRESSES.slice(0, 1))
    await upgradeSystemContractByteCode(UPGRADABLE_ADDRESSES.slice(1, 4))
    await upgradeSystemContractByteCode(UPGRADABLE_ADDRESSES.slice(4))
    console.log(`---------------------------`);
    console.log()
  } else if (!UPGRADABLE_ADDRESSES.includes(contractAddress)) {
    throw new Error(`Not supported contract address: ${contractAddress}`)
  } else {
    await upgradeSystemContractByteCode(contractAddress)
  }
})();