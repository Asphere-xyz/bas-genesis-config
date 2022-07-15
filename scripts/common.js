const {rlp, toBuffer} = require("ethereumjs-util");
const {padLeft} = require("web3-utils");

const blockToRlp = (block) => {
  return rlp.encode([
    toBuffer(block.parentHash),
    toBuffer(block.sha3Uncles),
    toBuffer(block.miner),
    toBuffer(block.stateRoot),
    toBuffer(block.transactionsRoot),
    toBuffer(block.receiptsRoot),
    toBuffer(block.logsBloom),
    Number(block.difficulty),
    Number(block.number),
    Number(block.gasLimit),
    Number(block.gasUsed),
    Number(block.timestamp),
    toBuffer(block.extraData),
    toBuffer(block.mixHash),
    padLeft(block.nonce, 8),
  ])
}

module.exports = {
  blockToRlp,
}