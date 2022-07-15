const {BaseTrie} = require('merkle-patricia-tree'),
  Web3 = require('web3');
const {hexToNumber, numberToHex} = require("web3-utils"),
  {rlp, toBuffer} = require("ethereumjs-util");
const {blockToRlp} = require("./common");

const sendJsonRpcRequest = async (web3, data) => {
  return new Promise((resolve, reject) => {
    web3.currentProvider.send(data, (error, result) => {
      if (error) return reject(error);
      if (result.error) return reject(result.error)
      resolve(result.result);
    })
  })
}

const isTypedReceipt = (receipt) => {
  if (!receipt.type) return false;
  const hexType = typeof receipt.type === 'number' ? numberToHex(receipt.type) : receipt.type;
  return receipt.status != null && hexType !== "0x0" && hexType !== "0x";
}

const getReceiptBytes = (receipt) => {
  let encodedData = rlp.encode([
    toBuffer(hexToNumber(receipt.status)),
    toBuffer(hexToNumber(receipt.cumulativeGasUsed)),
    toBuffer(receipt.logsBloom),
    // encoded log array
    receipt.logs.map(l => {
      // [address, [topics array], data]
      return [
        toBuffer(l.address), // convert address to buffer
        l.topics.map(toBuffer), // convert topics to buffer
        toBuffer(l.data), // convert data to buffer
      ];
    }),
  ]);
  if (isTypedReceipt(receipt)) {
    encodedData = Buffer.concat([toBuffer(receipt.type), encodedData]);
  }
  return encodedData;
}

const main = async () => {
  const [, , rpcUrl, txHash] = process.argv
  if (!rpcUrl || !txHash) {
    return console.error(`Node url and transaction hash params are not specified`)
  }

  const web3 = new Web3(rpcUrl);
  const receipt = await web3.eth.getTransactionReceipt(txHash)
  const block = await web3.eth.getBlock(receipt.blockNumber)

  console.log(`Receipts Root: ${block.receiptsRoot}`);
  console.log(`State Root: ${block.stateRoot}`);
  console.log(`Transactions Root: ${block.transactionsRoot}`);

  let receipts = await sendJsonRpcRequest(web3, {
    jsonrpc: '2.0',
    method: 'eth_getTransactionReceiptsByBlockNumber',
    params: [numberToHex(block.number)],
    id: 1,
  })
  receipts = receipts.map(r => {
    if (!r.type) r.type = 0
    return r
  })
  const receiptKey = rlp.encode(hexToNumber(receipt.transactionIndex));

  // build receipt trie
  const trie = new BaseTrie();
  for (const receipt of receipts) {
    const path = rlp.encode(hexToNumber(receipt.transactionIndex)),
      data = getReceiptBytes(receipt);
    await trie.put(path, data)
  }
  const foundPath = await trie.findPath(receiptKey, true)
  if (foundPath.remaining.length > 0) {
    throw new Error(`Can't find node in the trie`)
  }
  if (trie.root.toString('hex') !== block.receiptsRoot.substr(2)) {
    throw new Error(`Incorrect receipts root: ${trie.root.toString('hex')} != ${block.receiptsRoot.substr(2)}`)
  }

  // create some block proofs
  let blockProofs = [blockToRlp(block).toString('hex')];
  for (let i = 1; i < 5; i++) {
    const nextBlock = await web3.eth.getBlock(block.number+i)
    blockProofs.push(blockToRlp(nextBlock).toString('hex'));
  }

  // create proof
  const proof = {
    blockProofs: blockProofs,
    blockHash: receipt.blockHash,
    parentNodes: '0x' + rlp.encode(foundPath.stack.map(s => s.raw())).toString('hex'),
    root: '0x' + trie.root.toString('hex'),
    path: '0x' + Buffer.concat([Buffer.from('00', 'hex'), receiptKey]).toString('hex'),
  };
  if (isTypedReceipt(receipt)) {
    proof.value = '0x' + foundPath.node.value.toString('hex');
  } else {
    proof.value = '0x' + foundPath.node.value.toString('hex');
  }

  console.log();
  console.log('-----------------------------');
  console.log();
  console.log(JSON.stringify(proof, null, 2));
  console.log();
  console.log('-----------------------------');
  console.log();
};

main().catch(console.error)