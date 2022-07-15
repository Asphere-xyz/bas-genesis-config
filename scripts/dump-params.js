const Web3 = require('web3');
const {numberToHex, padLeft} = require("web3-utils"),
  {rlp, toBuffer} = require("ethereumjs-util");
const fs = require('fs');
const {blockToRlp} = require("./common");

const PARLIA_DEFAULT_EPOCH_LENGTH = 200;

const createChainParams = async (rpcUrl, targetFile) => {
  const web3 = new Web3(rpcUrl);
  const chainId = await web3.eth.getChainId(),
    genesisBlock = await web3.eth.getBlock('0')
  const rawGenesisBlock = blockToRlp(genesisBlock)
  let epochLength = PARLIA_DEFAULT_EPOCH_LENGTH
  const rawEpochLength = await web3.eth.call({
    // chain config contract
    to: '0x0000000000000000000000000000000000007003',
    // calling of "getEpochBlockInterval" method
    data: '0x346c90a8',
  })
  if (rawEpochLength.length > 2) {
    epochLength = Number.parseInt(rawEpochLength, 16)
  }
  console.log(`Hex chain id: ${numberToHex(chainId)}`);
  console.log(`Raw genesis block: 0x${rawGenesisBlock.toString('hex')}`)
  if (targetFile) {
    console.log(`Dumping chain params to file: ${targetFile}`);
    fs.writeFileSync(targetFile, JSON.stringify({
      chainId: numberToHex(chainId),
      genesisBlock: `0x${rawGenesisBlock.toString('hex')}`,
      epochLength: epochLength,
    }, null, 2));
  }
};

const DEFAULT_CHAIN_PARAMS = [
  ['bas-devnet-1', 'https://rpc.dev-01.bas.ankr.com/'],
  ['bas-devnet-2', 'https://rpc.dev-02.bas.ankr.com/'],
  ['bsc', 'https://rpc.ankr.com/bsc'],
  ['chapel', 'https://data-seed-prebsc-1-s1.binance.org:8545/'],
];

const main = async () => {
  const [, scriptPath, rpcUrl, targetFile] = process.argv;
  if (rpcUrl) {
    return createChainParams(rpcUrl, targetFile)
  }
  let parentPath;
  {
    const slices = scriptPath.split('/')
    parentPath = slices.slice(0, slices.length - 2).join('/')
    if (parentPath.endsWith('/')) {
      parentPath = parentPath.substring(0, parentPath.length - 1)
    }
  }
  for (const [chainName, rpcUrl] of DEFAULT_CHAIN_PARAMS) {
    await createChainParams(rpcUrl, `${parentPath}/params/${chainName}.json`);
  }
}

main().catch(console.error)