const eth = require('ethereumjs-util')
const rlp = require('rlp')
const Web3 = require('web3');

/** @var web3 {Web3} */

function operatorByNetwork(networkName) {
  const operatorByNetwork = {
    // BSC
    'smartchaintestnet': '0x256e78f10eE9897bda1c36C30471A2b3c8aE5186',
    'smartchain': '0x4069D8A3dE3A72EcA86CA5e0a4B94619085E7362',
    // ETH
    'goerli': '0x256e78f10eE9897bda1c36C30471A2b3c8aE5186',
    'mainnet': '0x4069D8A3dE3A72EcA86CA5e0a4B94619085E7362',
    // polygon
    'polygontestnet': '0x256e78f10eE9897bda1c36C30471A2b3c8aE5186',
    'polygon': '0x4069D8A3dE3A72EcA86CA5e0a4B94619085E7362',
    // unit tests
    'test': '0x256e78f10eE9897bda1c36C30471A2b3c8aE5186',
    'soliditycoverage': '0x256e78f10eE9897bda1c36C30471A2b3c8aE5186',
    'ganache': '0x256e78f10eE9897bda1c36C30471A2b3c8aE5186',
  };
  const operatorAddress = operatorByNetwork[networkName]
  if (!operatorAddress) throw new Error(`Operator doesn't exist for network ${networkName}`)
  return operatorAddress;
}

function nameAndSymbolByNetwork(networkName) {
  const networks = {
    // BSC
    'smartchaintestnet': {name: 'BNB', symbol: 'BNB'},
    'smartchain': {name: 'BNB', symbol: 'BNB'},
    // ETH
    'goerli': {name: 'Ethereum', symbol: 'ETH'},
    'mainnet': {name: 'Ethereum', symbol: 'ETH'},
    // polygon
    'polygontestnet': {name: 'Matic Token', symbol: 'MATIC'},
    'polygon': {name: 'Matic Token', symbol: 'MATIC'},
    // unit tests
    'test': {name: 'Ethereum', symbol: 'ETH'},
    'soliditycoverage': {name: 'Ethereum', symbol: 'ETH'},
    'ganache': {name: 'Ethereum', symbol: 'ETH'},
  };
  if (!networks[networkName]) throw new Error(`Unknown network ${networkName}`);
  return networks[networkName];
}

function nativeAddressByNetwork(networkName) {
  function nativeHash(str) {
    return '0x' + eth.keccak256(Buffer.from(str, 'utf8')).slice(0, 20).toString('hex');
  }

  const {symbol} = nameAndSymbolByNetwork(networkName);
  return nativeHash(`CrossChainBridge:${symbol}`);
}

function simpleTokenProxyAddress(deployer, salt) {
  if (deployer.startsWith('0x')) {
    deployer = deployer.substr(2);
  }
  if (salt.startsWith('0x')) {
    salt = salt.substr(2);
  }
  const {bytecode} = artifacts.require('PegTokenBeaconProxy');
  const byteCodeHash = eth.keccak256(eth.toBuffer(bytecode));
  const newAddress = eth.keccak256(eth.toBuffer([
    '0xff',
    deployer,
    web3.utils.padRight(salt, 64),
    byteCodeHash.toString('hex')
  ].join('')));
  return `0x${newAddress.toString('hex').substr(24)}`;
}

function createSimpleTokenMetaData(symbol, name, chain, origin) {
  return [
    web3.eth.abi.encodeParameter('bytes32', web3.utils.asciiToHex(symbol)),
    web3.eth.abi.encodeParameter('bytes32', web3.utils.asciiToHex(name)),
    origin
  ];
}

function encodeTransactionReceipt(txReceipt) {
  const rlpLogs = txReceipt.rawLogs.map(log => {
    return [
      // address
      log.address,
      // topics
      log.topics,
      // data
      new Buffer(log.data.substr(2), 'hex'),
    ];
  });
  const rlpReceipt = [
    // postStateOrStatus
    Number(txReceipt.status),
    // cumulativeGasUsed
    Web3.utils.numberToHex(txReceipt.gasUsed),
    // bloom
    txReceipt.logsBloom,
    // logs
    rlpLogs,
  ];
  const encodedReceipt = rlp.encode(rlpReceipt),
    receiptHash = eth.keccak256(encodedReceipt);
  return [`0x${encodedReceipt.toString('hex')}`, `0x${receiptHash.toString('hex')}`];
}

function encodeProof(chainId, status, txHash, blockNumber, blockHash, txIndex, receiptHash, amount) {
  const proofData = Buffer.concat([
    new Buffer(web3.eth.abi.encodeParameters(['uint256', 'uint256'], [chainId, status]).substr(2), 'hex'),
    new Buffer(txHash.substr(2), 'hex'),
    new Buffer(blockNumber.substr(2), 'hex'),
    new Buffer(blockHash.substr(2), 'hex'),
    new Buffer(txIndex.substr(2), 'hex'),
    new Buffer(receiptHash.substr(2), 'hex'),
    new Buffer(amount.substr(2), 'hex'),
  ]);
  const encodedProof = Buffer.concat([
      new Buffer(web3.eth.abi.encodeParameters(['uint256'], [chainId]).substr(2), 'hex'),
      new Buffer(txHash.substr(2), 'hex'),
      new Buffer(blockNumber.substr(2), 'hex'),
      new Buffer(blockHash.substr(2), 'hex'),
      new Buffer(txIndex.substr(2), 'hex'),
      new Buffer(amount.substr(2), 'hex'),
    ]),
    proofHash = eth.keccak256(proofData);
  return [`0x${encodedProof.toString('hex')}`, `0x${proofHash.toString('hex')}`];
}

module.exports = {
  createSimpleTokenMetaData,
  operatorByNetwork,
  nameAndSymbolByNetwork,
  nativeAddressByNetwork,
  simpleTokenProxyAddress,
  encodeTransactionReceipt,
  encodeProof,
};
