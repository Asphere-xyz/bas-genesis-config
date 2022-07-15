/** @var artifacts {Array} */
/** @var web3 {Web3} */
/** @function contract */
/** @function it */
/** @function before */
/** @var assert */

const CrossChainBridge = artifacts.require("TestCrossChainBridge");
const SimpleTokenFactory = artifacts.require("SimpleTokenFactory");
const SimpleToken = artifacts.require("SimpleToken");
const BridgeRouter = artifacts.require("BridgeRouter");
const TestTokenFactory = artifacts.require("TestTokenFactory");
const TestRelayHub = artifacts.require("TestRelayHub");

const {
  createSimpleTokenMetaData,
  nativeAddressByNetwork,
  encodeTransactionReceipt,
  simpleTokenProxyAddress,
  nameAndSymbolByNetwork,
} = require('./bridge-utils');

const {
  expectError
} = require('./evm-utils');

const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

contract("CrossChainBridge", function (accounts) {

  let [owner, recipient] = accounts;

  const getFixedChainId = async () => {
    let chainId = await web3.eth.getChainId();
    // use default 1 chain id for ganache because CHAINID opcode returns always 1
    if (global.config.network === 'ganache') {
      chainId = 1;
    }
    return chainId;
  }

  const createCrossChainBridge = async (tokenFactory) => {
    const chainId = await getFixedChainId();
    // token factory
    if (!tokenFactory) {
      tokenFactory = await SimpleTokenFactory.new();
    }
    // router
    const bridgeRouter = await BridgeRouter.new(),
      basRelayHub = await TestRelayHub.new();
    // bridge
    const crossChainBridge = await CrossChainBridge.new();
    const {name, symbol} = nameAndSymbolByNetwork('test');
    await crossChainBridge.initialize(basRelayHub.address, basRelayHub.address, tokenFactory.address, bridgeRouter.address, symbol, name);
    // enable cross chain bridge
    await basRelayHub.enableCrossChainBridge(chainId, crossChainBridge.address);
    return crossChainBridge;
  }

  describe("pegged tokens are working correctly", async () => {

    let crossChainBridge, simpleToken1, simpleToken2, chainId;
    const maxUInt256 = '115792089237316195423570985008687907853269984665640564039457584007913129639935'; // 2 ** 256 - 1

    before(async function () {
      chainId = await getFixedChainId();
      crossChainBridge = await createCrossChainBridge();
      // tokens
      simpleToken1 = await SimpleToken.new();
      await simpleToken1.initialize(web3.utils.fromAscii('Ankr'), web3.utils.fromAscii('Ankr Network'), 0, ZERO_ADDRESS, {from: owner});
      await simpleToken1.mint(owner, '100000000000000000000');
      simpleToken2 = await SimpleToken.new();
      await simpleToken2.initialize(web3.utils.fromAscii('Bnkr'), web3.utils.fromAscii('Bnkr Network'), 0, ZERO_ADDRESS, {from: owner});
      await simpleToken2.mint(owner, maxUInt256);
    });

    it("warmup pegged tokens", async () => {
      // warmup pegged ethereum
      assert.equal(await crossChainBridge.isPeggedToken(simpleTokenProxyAddress(crossChainBridge.address, nativeAddressByNetwork('test'))), false);
      await crossChainBridge.factoryPeggedToken(chainId, createSimpleTokenMetaData('ETH', 'Ethereum', chainId, nativeAddressByNetwork('test')));
      assert.equal(await crossChainBridge.isPeggedToken(simpleTokenProxyAddress(crossChainBridge.address, nativeAddressByNetwork('test'))), true);
      // warmup pegged ankr
      assert.equal(await crossChainBridge.isPeggedToken(simpleTokenProxyAddress(crossChainBridge.address, simpleToken1.address).toLowerCase()), false);
      await crossChainBridge.factoryPeggedToken(chainId, createSimpleTokenMetaData('ANKR', 'Ankr Network', chainId, simpleToken1.address));
      assert.equal(await crossChainBridge.isPeggedToken(simpleTokenProxyAddress(crossChainBridge.address, simpleToken1.address).toLowerCase()), true);
    })

    it("pegged native token works", async () => {
      const tx1 = await crossChainBridge.deposit(chainId, owner, {value: '10000', from: owner});
      const pegTokenAddress = simpleTokenProxyAddress(crossChainBridge.address, nativeAddressByNetwork('test')).toLowerCase();
      const [rawReceipt] = encodeTransactionReceipt(tx1.receipt);
      await crossChainBridge.withdraw([], rawReceipt, '0x', '0x', {from: owner});
      const pegToken = new SimpleToken(pegTokenAddress);
      const peggedBalance = await pegToken.balanceOf(owner),
        lockedBalance = await web3.eth.getBalance(crossChainBridge.address);
      assert.equal(peggedBalance.toString(10), '10000');
      assert.equal(peggedBalance.toString(10), lockedBalance.toString(10));
      await runTokenTestSuite(pegToken, {
        shouldBeName: 'Ethereum',
        shouldBeDecimals: 18,
        shouldBeSymbol: 'ETH'
      });
    });

    it("pegged simple ERC20 token works", async () => {
      await simpleToken1.approve(crossChainBridge.address, '10000');
      let tx1 = await crossChainBridge.deposit(simpleToken1.address, chainId, owner, '10000');
      const pegTokenAddress = simpleTokenProxyAddress(crossChainBridge.address, simpleToken1.address).toLowerCase();
      const [rawReceipt] = encodeTransactionReceipt(tx1.receipt);
      await crossChainBridge.withdraw([], rawReceipt, '0x', '0x', {from: owner});
      const pegToken = new SimpleToken(pegTokenAddress);
      const peggedBalance = await pegToken.balanceOf(owner),
        lockedBalance = await simpleToken1.balanceOf(crossChainBridge.address);
      assert.equal(peggedBalance.toString(10), '10000');
      assert.equal(peggedBalance.toString(10), lockedBalance.toString(10));

      await runTokenTestSuite(pegToken, {
        shouldBeName: 'Ankr Network',
        shouldBeDecimals: 18,
        shouldBeSymbol: 'ANKR'
      });
    });

    it("can bridge max uint256 of ERC20", async () => {
      await simpleToken2.approve(crossChainBridge.address, maxUInt256);
      let tx1 = await crossChainBridge.deposit(simpleToken2.address, chainId, owner, maxUInt256);
      const pegTokenAddress = simpleTokenProxyAddress(crossChainBridge.address, simpleToken2.address).toLowerCase();
      const [rawReceipt, receiptHash] = encodeTransactionReceipt(tx1.receipt);
      await crossChainBridge.withdraw([], rawReceipt, '0x', '0x', {from: owner});
      const pegToken = new SimpleToken(pegTokenAddress);
      const peggedBalance = await pegToken.balanceOf(owner),
        lockedBalance = await simpleToken2.balanceOf(crossChainBridge.address);
      assert.equal(peggedBalance.toString(10), maxUInt256);
      assert.equal(peggedBalance.toString(10), lockedBalance.toString(10));
    });
  });

  describe("use pre-deployed pegged contracts", async () => {

    let crossChainBridge, ankrToken, chainId;

    before(async function () {
      chainId = await getFixedChainId();
      crossChainBridge = await createCrossChainBridge();
      // tokens
      ankrToken = await SimpleToken.new();
      await ankrToken.initialize(web3.utils.fromAscii('Ankr'), web3.utils.fromAscii('Ankr'), 0, ZERO_ADDRESS, {from: owner});
      await ankrToken.mint(owner, '100000000000000000000');
    });

    it("warmup pegged tokens", async () => {
      // warmup pegged ethereum
      assert.equal(await crossChainBridge.isPeggedToken(simpleTokenProxyAddress(crossChainBridge.address, nativeAddressByNetwork('test'))), false);
      await crossChainBridge.factoryPeggedToken(chainId, createSimpleTokenMetaData('ETH', 'Ethereum', chainId, nativeAddressByNetwork('test')));
      assert.equal(await crossChainBridge.isPeggedToken(simpleTokenProxyAddress(crossChainBridge.address, nativeAddressByNetwork('test'))), true);
      // warmup pegged ankr
      assert.equal(await crossChainBridge.isPeggedToken(simpleTokenProxyAddress(crossChainBridge.address, ankrToken.address).toLowerCase()), false);
      await crossChainBridge.factoryPeggedToken(chainId, createSimpleTokenMetaData('ANKR', 'Ankr Network', chainId, ankrToken.address));
      assert.equal(await crossChainBridge.isPeggedToken(simpleTokenProxyAddress(crossChainBridge.address, ankrToken.address).toLowerCase()), true);
    })

    it("peg-in native to pegged (lock)", async () => {
      // deposit tokens to smart contract (peg-in)
      let tx1 = await crossChainBridge.deposit(chainId, recipient, {value: '1', from: owner}),
        logs1 = tx1.logs;
      // console.log(`Gas for (lock native -> mint pegged)`);
      // console.log(` ~ Peg-In gas used: ${tx1.receipt.cumulativeGasUsed}`);
      const pegTokenAddress = simpleTokenProxyAddress(crossChainBridge.address, nativeAddressByNetwork('test')).toLowerCase();
      assert.equal(logs1[0].event, 'DepositLocked');
      assert.equal(logs1[0].args['fromAddress'], owner);
      assert.equal(logs1[0].args['toAddress'], recipient);
      assert.equal(logs1[0].args['fromToken'].toLowerCase(), nativeAddressByNetwork('test').toLowerCase());
      assert.equal(logs1[0].args['toToken'].toLowerCase(), pegTokenAddress);
      assert.equal(logs1[0].args['totalAmount'].toString(10), '1');

      // withdraw pegged token (peg-out)
      const [rawReceipt, receiptHash] = encodeTransactionReceipt(tx1.receipt);
      let tx2 = await crossChainBridge.withdraw([], rawReceipt, '0x', '0x', {from: recipient}),
        logs2 = tx2.logs;
      // console.log(` ~ Peg-Out gas used: ${tx2.receipt.cumulativeGasUsed}`);
      assert.equal(logs2[0].event, 'WithdrawMinted');
      assert.equal(logs2[0].args['receiptHash'], receiptHash);
      assert.equal(logs2[0].args['fromAddress'], owner);
      assert.equal(logs2[0].args['toAddress'], recipient);
      assert.equal(logs2[0].args['fromToken'].toLowerCase(), nativeAddressByNetwork('test').toLowerCase());
      assert.equal(logs2[0].args['toToken'].toLowerCase(), pegTokenAddress);
      assert.equal(logs2[0].args['totalAmount'].toString(10), '1');
      // check pegged tokens
      const pegToken = new SimpleToken(pegTokenAddress);
      assert.equal(await pegToken.symbol(), 'ETH');
      assert.equal(await pegToken.name(), 'Ethereum');
      assert.equal(await pegToken.decimals(), '18');
      const peggedBalance = await pegToken.balanceOf(recipient),
        lockedBalance = await web3.eth.getBalance(crossChainBridge.address);
      assert.equal(peggedBalance.toString(10), '1');
      assert.equal(peggedBalance.toString(10), lockedBalance.toString(10));
      const tx3 = await pegToken.transfer(owner, '1', {from: recipient}),
        logs3 = tx3.logs;
      assert.equal(logs3[0].event, 'Transfer');
      assert.equal(logs3[0].args['from'], recipient);
      assert.equal(logs3[0].args['to'], owner);
      assert.equal(logs3[0].args['value'].toString(10), '1');
    });

    it("peg-in pegged to native (burn)", async () => {
      // pegged token address
      const pegTokenAddress = simpleTokenProxyAddress(crossChainBridge.address, nativeAddressByNetwork('test')).toLowerCase();
      const pegToken = new SimpleToken(pegTokenAddress);
      // deposit pegged tokens to smart contract (peg-in)
      const isPegged = await crossChainBridge.isPeggedToken(pegToken.address);
      assert.equal(isPegged, true);
      let tx1 = await crossChainBridge.deposit(pegToken.address, chainId, recipient, '1'),
        logs1 = tx1.logs;
      // console.log(`Gas for (burn pegged -> unlock native)`);
      // console.log(` ~ Peg-In gas used: ${tx1.receipt.cumulativeGasUsed}`);
      assert.equal(logs1[0].event, 'DepositBurned');
      assert.equal(logs1[0].args['fromAddress'].toLowerCase(), owner.toLowerCase());
      assert.equal(logs1[0].args['toAddress'].toLowerCase(), recipient.toLowerCase());
      assert.equal(logs1[0].args['fromToken'].toLowerCase(), pegTokenAddress);
      assert.equal(logs1[0].args['toToken'].toLowerCase(), nativeAddressByNetwork('test'));
      assert.equal(logs1[0].args['totalAmount'].toString(10), '1');
      // withdraw native tokens
      const [rawReceipt, receiptHash] = encodeTransactionReceipt(tx1.receipt);
      let tx2 = await crossChainBridge.withdraw([], rawReceipt, '0x', '0x', {from: recipient}),
        logs2 = tx2.logs;
      // console.log(` ~ Peg-Out gas used: ${tx2.receipt.cumulativeGasUsed}`);
      assert.equal(logs2[0].event, 'WithdrawUnlocked');
      assert.equal(logs2[0].args['receiptHash'], receiptHash);
      assert.equal(logs2[0].args['fromAddress'].toLowerCase(), owner.toLowerCase());
      assert.equal(logs2[0].args['toAddress'].toLowerCase(), recipient.toLowerCase());
      assert.equal(logs2[0].args['fromToken'].toLowerCase(), pegTokenAddress);
      assert.equal(logs2[0].args['toToken'].toLowerCase(), nativeAddressByNetwork('test'));
      assert.equal(logs2[0].args['totalAmount'].toString(10), '1');
    });

    it("peg-in erc20 to pegged (lock)", async () => {
      // deposit tokens to smart contract (peg-in)
      await ankrToken.approve(crossChainBridge.address, '1');
      let tx1 = await crossChainBridge.deposit(ankrToken.address, chainId, recipient, '1'),
        logs1 = tx1.logs;
      // console.log(`Gas for (lock erc20 -> mint pegged)`);
      // console.log(` ~ Peg-In gas used: ${tx1.receipt.cumulativeGasUsed}`);
      const pegTokenAddress = simpleTokenProxyAddress(crossChainBridge.address, ankrToken.address).toLowerCase();
      assert.equal(logs1[0].event, 'DepositLocked');
      assert.equal(logs1[0].args['fromAddress'], owner);
      assert.equal(logs1[0].args['toAddress'], recipient);
      assert.equal(logs1[0].args['fromToken'].toLowerCase(), ankrToken.address.toLowerCase());
      assert.equal(logs1[0].args['toToken'].toLowerCase(), pegTokenAddress);
      assert.equal(logs1[0].args['totalAmount'].toString(10), '1');
      // withdraw pegged token (peg-out)
      const [rawReceipt, receiptHash] = encodeTransactionReceipt(tx1.receipt);
      let tx2 = await crossChainBridge.withdraw([], rawReceipt, '0x', '0x', {from: recipient}),
        logs2 = tx2.logs;
      // console.log(`Peg-Out gas used: ${tx2.receipt.cumulativeGasUsed}`);
      assert.equal(logs2[0].event, 'WithdrawMinted');
      assert.equal(logs2[0].args['receiptHash'], receiptHash);
      assert.equal(logs2[0].args['fromAddress'], owner);
      assert.equal(logs2[0].args['toAddress'], recipient);
      assert.equal(logs2[0].args['fromToken'].toLowerCase(), ankrToken.address.toLowerCase());
      assert.equal(logs2[0].args['toToken'].toLowerCase(), pegTokenAddress);
      assert.equal(logs1[0].args['totalAmount'].toString(10), '1');
      // check pegged tokens
      const pegToken = new SimpleToken(pegTokenAddress);
      const peggedBalance = await pegToken.balanceOf(recipient),
        lockedBalance = await ankrToken.balanceOf(crossChainBridge.address);
      assert.equal(peggedBalance.toString(10), '1');
      assert.equal(peggedBalance.toString(10), lockedBalance.toString(10));
      // transfer to the owner
      await pegToken.transfer(owner, '1', {from: recipient});
      assert.equal(await pegToken.symbol(), 'ANKR');
      assert.equal(await pegToken.name(), 'Ankr Network');
      assert.equal(await pegToken.decimals(), '18');
    });

    it("peg-in pegged to erc20 (burn)", async () => {
      // pegged token address
      const pegTokenAddress = simpleTokenProxyAddress(crossChainBridge.address, ankrToken.address).toLowerCase();
      const pegToken = new SimpleToken(pegTokenAddress);
      // deposit pegged tokens to smart contract (peg-in)
      const isPegged = await crossChainBridge.isPeggedToken(pegToken.address);
      assert.equal(isPegged, true);
      let tx1 = await crossChainBridge.deposit(pegToken.address, chainId, recipient, '1'),
        logs1 = tx1.logs;
      // console.log(`Gas for (burn pegged -> unlock erc20)`);
      // console.log(` ~ Peg-In gas used: ${tx1.receipt.cumulativeGasUsed}`);
      assert.equal(logs1[0].event, 'DepositBurned');
      assert.equal(logs1[0].args['fromAddress'].toLowerCase(), owner.toLowerCase());
      assert.equal(logs1[0].args['toAddress'].toLowerCase(), recipient.toLowerCase());
      assert.equal(logs1[0].args['fromToken'].toLowerCase(), pegTokenAddress.toLowerCase());
      assert.equal(logs1[0].args['toToken'].toLowerCase(), ankrToken.address.toLowerCase());
      assert.equal(logs1[0].args['totalAmount'].toString(10), '1');
      // withdraw native tokens
      const [rawReceipt, receiptHash] = encodeTransactionReceipt(tx1.receipt);
      let tx2 = await crossChainBridge.withdraw([], rawReceipt, '0x', '0x', {from: recipient}),
        logs2 = tx2.logs;
      // console.log(` ~ Peg-Out gas used: ${tx2.receipt.cumulativeGasUsed}`);
      assert.equal(logs2[0].event, 'WithdrawUnlocked');
      assert.equal(logs2[0].args['receiptHash'], receiptHash);
      assert.equal(logs2[0].args['fromAddress'].toLowerCase(), owner.toLowerCase());
      assert.equal(logs2[0].args['toAddress'].toLowerCase(), recipient.toLowerCase());
      assert.equal(logs2[0].args['fromToken'].toLowerCase(), pegTokenAddress.toLowerCase());
      assert.equal(logs2[0].args['toToken'].toLowerCase(), ankrToken.address.toLowerCase());
      assert.equal(logs2[0].args['totalAmount'].toString(10), '1');
    });

    it("switch to new token implementation", async () => {
      const pegTokenAddress = simpleTokenProxyAddress(crossChainBridge.address, nativeAddressByNetwork('test')).toLowerCase();
      const pegToken = new SimpleToken(pegTokenAddress);

      assert.equal(await pegToken.symbol(), 'ETH');
      assert.equal(await pegToken.name(), 'Ethereum');
      assert.equal(await pegToken.decimals(), '18');

      // test token factory
      const testFactory = await TestTokenFactory.new();
      await crossChainBridge.setTokenFactory(testFactory.address);

      assert.equal(await pegToken.symbol(), 'ETH');
      assert.equal(await pegToken.name(), 'Ethereum');
      assert.equal((await pegToken.decimals()).toString(10), '18');
    });
  });

  describe("deploy pegged contracts on the fly", async () => {

    let crossChainBridge, ankrToken, chainId;

    before(async function () {
      chainId = await getFixedChainId();
      crossChainBridge = await createCrossChainBridge();
      // tokens
      ankrToken = await SimpleToken.new();
      await ankrToken.initialize(web3.utils.fromAscii('Ankr'), web3.utils.fromAscii('Ankr'), 0, ZERO_ADDRESS, {from: owner});
      await ankrToken.mint(owner, '100000000000000000000');
    });

    it("peg-in native to pegged (lock)", async () => {
      // deposit tokens to smart contract (peg-in)
      let tx1 = await crossChainBridge.deposit(chainId, recipient, {value: '1', from: owner}),
        logs1 = tx1.logs;
      // console.log(`Gas for (lock native -> mint pegged)`);
      // console.log(` ~ Peg-In gas used: ${tx1.receipt.cumulativeGasUsed}`);
      const pegTokenAddress = simpleTokenProxyAddress(crossChainBridge.address, nativeAddressByNetwork('test')).toLowerCase();
      assert.equal(logs1[0].event, 'DepositLocked');
      assert.equal(logs1[0].args['fromAddress'], owner);
      assert.equal(logs1[0].args['toAddress'], recipient);
      assert.equal(logs1[0].args['fromToken'].toLowerCase(), nativeAddressByNetwork('test').toLowerCase());
      assert.equal(logs1[0].args['toToken'].toLowerCase(), pegTokenAddress);
      assert.equal(logs1[0].args['totalAmount'].toString(10), '1');
      // withdraw pegged token (peg-out)
      const [rawReceipt, receiptHash] = encodeTransactionReceipt(tx1.receipt);
      let tx2 = await crossChainBridge.withdraw([], rawReceipt, '0x', '0x', {from: recipient}),
        logs2 = tx2.logs;
      // console.log(` ~ Peg-Out gas used: ${tx2.receipt.cumulativeGasUsed}`);
      assert.equal(logs2[0].event, 'WithdrawMinted');
      assert.equal(logs2[0].args['receiptHash'], receiptHash);
      assert.equal(logs2[0].args['fromAddress'], owner);
      assert.equal(logs2[0].args['toAddress'], recipient);
      assert.equal(logs2[0].args['fromToken'].toLowerCase(), nativeAddressByNetwork('test').toLowerCase());
      assert.equal(logs2[0].args['toToken'].toLowerCase(), pegTokenAddress);
      assert.equal(logs2[0].args['totalAmount'].toString(10), '1');
      // check pegged tokens
      const pegToken = new SimpleToken(pegTokenAddress);
      assert.equal(await pegToken.symbol(), 'ETH');
      assert.equal(await pegToken.name(), 'Ethereum');
      assert.equal(await pegToken.decimals(), '18');
      const peggedBalance = await pegToken.balanceOf(recipient),
        lockedBalance = await web3.eth.getBalance(crossChainBridge.address);
      assert.equal(peggedBalance.toString(10), '1');
      assert.equal(peggedBalance.toString(10), lockedBalance.toString(10));
      const tx3 = await pegToken.transfer(owner, '1', {from: recipient}),
        logs3 = tx3.logs;
      assert.equal(logs3[0].event, 'Transfer');
      assert.equal(logs3[0].args['from'], recipient);
      assert.equal(logs3[0].args['to'], owner);
      assert.equal(logs3[0].args['value'].toString(10), '1');
    });

    it("peg-in pegged to native (burn)", async () => {
      // pegged token address
      const pegTokenAddress = simpleTokenProxyAddress(crossChainBridge.address, nativeAddressByNetwork('test')).toLowerCase();
      const pegToken = new SimpleToken(pegTokenAddress);
      // deposit pegged tokens to smart contract (peg-in)
      const isPegged = await crossChainBridge.isPeggedToken(pegToken.address);
      assert.equal(isPegged, true);
      let tx1 = await crossChainBridge.deposit(pegToken.address, chainId, recipient, '1'),
        logs1 = tx1.logs;
      // console.log(`Gas for (burn pegged -> unlock native)`);
      // console.log(` ~ Peg-In gas used: ${tx1.receipt.cumulativeGasUsed}`);
      assert.equal(logs1[0].event, 'DepositBurned');
      assert.equal(logs1[0].args['fromAddress'].toLowerCase(), owner.toLowerCase());
      assert.equal(logs1[0].args['toAddress'].toLowerCase(), recipient.toLowerCase());
      assert.equal(logs1[0].args['fromToken'].toLowerCase(), pegTokenAddress);
      assert.equal(logs1[0].args['toToken'].toLowerCase(), nativeAddressByNetwork('test'));
      assert.equal(logs1[0].args['totalAmount'].toString(10), '1');
      // withdraw native tokens
      const [rawReceipt, receiptHash] = encodeTransactionReceipt(tx1.receipt);
      let tx2 = await crossChainBridge.withdraw([], rawReceipt, '0x', '0x', {from: recipient}),
        logs2 = tx2.logs;
      // console.log(` ~ Peg-Out gas used: ${tx2.receipt.cumulativeGasUsed}`);
      assert.equal(logs2[0].event, 'WithdrawUnlocked');
      assert.equal(logs2[0].args['receiptHash'], receiptHash);
      assert.equal(logs2[0].args['fromAddress'].toLowerCase(), owner.toLowerCase());
      assert.equal(logs2[0].args['toAddress'].toLowerCase(), recipient.toLowerCase());
      assert.equal(logs2[0].args['fromToken'].toLowerCase(), pegTokenAddress);
      assert.equal(logs2[0].args['toToken'].toLowerCase(), nativeAddressByNetwork('test'));
      assert.equal(logs2[0].args['totalAmount'].toString(10), '1');
    });

    it("peg-in erc20 to pegged (lock)", async () => {
      // deposit tokens to smart contract (peg-in)
      await ankrToken.approve(crossChainBridge.address, '1');
      let tx1 = await crossChainBridge.deposit(ankrToken.address, chainId, recipient, '1'),
        logs1 = tx1.logs;
      // console.log(`Gas for (lock erc20 -> mint pegged)`);
      // console.log(` ~ Peg-In gas used: ${tx1.receipt.cumulativeGasUsed}`);
      const pegTokenAddress = simpleTokenProxyAddress(crossChainBridge.address, ankrToken.address).toLowerCase();
      assert.equal(logs1[0].event, 'DepositLocked');
      assert.equal(logs1[0].args['fromAddress'], owner);
      assert.equal(logs1[0].args['toAddress'], recipient);
      assert.equal(logs1[0].args['fromToken'].toLowerCase(), ankrToken.address.toLowerCase());
      assert.equal(logs1[0].args['toToken'].toLowerCase(), pegTokenAddress);
      assert.equal(logs1[0].args['totalAmount'].toString(10), '1');
      // withdraw pegged token (peg-out)
      const [rawReceipt, receiptHash] = encodeTransactionReceipt(tx1.receipt);
      let tx2 = await crossChainBridge.withdraw([], rawReceipt, '0x', '0x', {from: recipient}),
        logs2 = tx2.logs;
      // console.log(`Peg-Out gas used: ${tx2.receipt.cumulativeGasUsed}`);
      assert.equal(logs2[0].event, 'WithdrawMinted');
      assert.equal(logs2[0].args['receiptHash'], receiptHash);
      assert.equal(logs2[0].args['fromAddress'], owner);
      assert.equal(logs2[0].args['toAddress'], recipient);
      assert.equal(logs2[0].args['fromToken'].toLowerCase(), ankrToken.address.toLowerCase());
      assert.equal(logs2[0].args['toToken'].toLowerCase(), pegTokenAddress);
      assert.equal(logs1[0].args['totalAmount'].toString(10), '1');
      // check pegged tokens
      const pegToken = new SimpleToken(pegTokenAddress);
      const peggedBalance = await pegToken.balanceOf(recipient),
        lockedBalance = await ankrToken.balanceOf(crossChainBridge.address);
      assert.equal(peggedBalance.toString(10), '1');
      assert.equal(peggedBalance.toString(10), lockedBalance.toString(10));
      // transfer to the owner
      await pegToken.transfer(owner, '1', {from: recipient});
      assert.equal(await pegToken.symbol(), 'Ankr');
      assert.equal(await pegToken.name(), 'Ankr');
      assert.equal(await pegToken.decimals(), '18');
    });

    it("peg-in pegged to erc20 (burn)", async () => {
      // pegged token address
      const pegTokenAddress = simpleTokenProxyAddress(crossChainBridge.address, ankrToken.address).toLowerCase();
      const pegToken = new SimpleToken(pegTokenAddress);
      // deposit pegged tokens to smart contract (peg-in)
      const isPegged = await crossChainBridge.isPeggedToken(pegToken.address);
      assert.equal(isPegged, true);
      let tx1 = await crossChainBridge.deposit(pegToken.address, chainId, recipient, '1'),
        logs1 = tx1.logs;
      // console.log(`Gas for (burn pegged -> unlock erc20)`);
      // console.log(` ~ Peg-In gas used: ${tx1.receipt.cumulativeGasUsed}`);
      assert.equal(logs1[0].event, 'DepositBurned');
      assert.equal(logs1[0].args['fromAddress'].toLowerCase(), owner.toLowerCase());
      assert.equal(logs1[0].args['toAddress'].toLowerCase(), recipient.toLowerCase());
      assert.equal(logs1[0].args['fromToken'].toLowerCase(), pegTokenAddress.toLowerCase());
      assert.equal(logs1[0].args['toToken'].toLowerCase(), ankrToken.address.toLowerCase());
      assert.equal(logs1[0].args['totalAmount'].toString(10), '1');
      // withdraw native tokens
      const [rawReceipt, receiptHash] = encodeTransactionReceipt(tx1.receipt);
      let tx2 = await crossChainBridge.withdraw([], rawReceipt, '0x', '0x', {from: recipient}),
        logs2 = tx2.logs;
      // console.log(` ~ Peg-Out gas used: ${tx2.receipt.cumulativeGasUsed}`);
      assert.equal(logs2[0].event, 'WithdrawUnlocked');
      assert.equal(logs2[0].args['receiptHash'], receiptHash);
      assert.equal(logs2[0].args['fromAddress'].toLowerCase(), owner.toLowerCase());
      assert.equal(logs2[0].args['toAddress'].toLowerCase(), recipient.toLowerCase());
      assert.equal(logs2[0].args['fromToken'].toLowerCase(), pegTokenAddress.toLowerCase());
      assert.equal(logs2[0].args['toToken'].toLowerCase(), ankrToken.address.toLowerCase());
      assert.equal(logs2[0].args['totalAmount'].toString(10), '1');
    });
  });

  describe("simulate different cross chain bridges", async () => {

    let tokenFactory, crossChainBridge0, crossChainBridge1, crossChainBridge2, ankrToken, chainId;

    before(async function () {
      chainId = await getFixedChainId();
      // token factory (use TestToken2 that allows minting by anyone)
      tokenFactory = await TestTokenFactory.new();
      // router
      const bridgeRouter = await BridgeRouter.new();
      const basRelayHub0 = await TestRelayHub.new();
      const basRelayHub1 = await TestRelayHub.new();
      const basRelayHub2 = await TestRelayHub.new();
      // bridge
      crossChainBridge0 = await CrossChainBridge.new();
      const {name, symbol} = nameAndSymbolByNetwork('test');
      await crossChainBridge0.initialize(basRelayHub0.address, basRelayHub0.address, tokenFactory.address, bridgeRouter.address, symbol, name);
      crossChainBridge1 = await CrossChainBridge.new();
      await crossChainBridge1.initialize(basRelayHub1.address, basRelayHub1.address, tokenFactory.address, bridgeRouter.address, symbol, name);
      crossChainBridge2 = await CrossChainBridge.new();
      await crossChainBridge2.initialize(basRelayHub2.address, basRelayHub2.address, tokenFactory.address, bridgeRouter.address, symbol, name);

      // tokens
      ankrToken = await SimpleToken.new();
      await ankrToken.initialize(web3.utils.fromAscii('Ankr'), web3.utils.fromAscii('Ankr'), 0, ZERO_ADDRESS, {from: owner});
      await ankrToken.mint(owner, '100000000000000000000');
    });

    it('add allowed contract', async () => {
      (await TestRelayHub.at(await crossChainBridge1.getRelayHub())).enableCrossChainBridge(chainId, crossChainBridge2.address);
      (await TestRelayHub.at(await crossChainBridge2.getRelayHub())).enableCrossChainBridge(chainId, crossChainBridge1.address);
      (await TestRelayHub.at(await crossChainBridge1.getRelayHub())).enableCrossChainBridge(chainId + 1, crossChainBridge0.address);
      (await TestRelayHub.at(await crossChainBridge2.getRelayHub())).enableCrossChainBridge(chainId + 1, crossChainBridge0.address);
    });

    it("warmup pegged tokens", async () => {
      // warmup pegged ethereum
      assert.equal(await crossChainBridge1.isPeggedToken(simpleTokenProxyAddress(crossChainBridge1.address, nativeAddressByNetwork('test'))), false);
      await crossChainBridge1.factoryPeggedToken(chainId + 1, createSimpleTokenMetaData('ETH', 'Ethereum', chainId + 1, nativeAddressByNetwork('test')));
      assert.equal(await crossChainBridge1.isPeggedToken(simpleTokenProxyAddress(crossChainBridge1.address, nativeAddressByNetwork('test'))), true);
      // warmup pegged ankr
      assert.equal(await crossChainBridge1.isPeggedToken(simpleTokenProxyAddress(crossChainBridge1.address, ankrToken.address).toLowerCase()), false);
      await crossChainBridge1.factoryPeggedToken(chainId + 1, createSimpleTokenMetaData('ANKR', 'Ankr Network', chainId + 1, ankrToken.address));
      assert.equal(await crossChainBridge1.isPeggedToken(simpleTokenProxyAddress(crossChainBridge1.address, ankrToken.address).toLowerCase()), true);
      // warmup pegged ethereum
      assert.equal(await crossChainBridge2.isPeggedToken(simpleTokenProxyAddress(crossChainBridge2.address, nativeAddressByNetwork('test'))), false);
      await crossChainBridge2.factoryPeggedToken(chainId + 1, createSimpleTokenMetaData('ETH', 'Ethereum', chainId + 1, nativeAddressByNetwork('test')));
      assert.equal(await crossChainBridge2.isPeggedToken(simpleTokenProxyAddress(crossChainBridge2.address, nativeAddressByNetwork('test'))), true);
      // warmup pegged ankr
      assert.equal(await crossChainBridge2.isPeggedToken(simpleTokenProxyAddress(crossChainBridge2.address, ankrToken.address).toLowerCase()), false);
      await crossChainBridge2.factoryPeggedToken(chainId + 1, createSimpleTokenMetaData('ANKR', 'Ankr Network', chainId + 1, ankrToken.address));
      assert.equal(await crossChainBridge2.isPeggedToken(simpleTokenProxyAddress(crossChainBridge2.address, ankrToken.address).toLowerCase()), true);
    })

    it("pegged (of native) to pegged (burn)", async () => {
      // deposit tokens to smart contract (peg-in)
      const pegTokenAddress1 = simpleTokenProxyAddress(crossChainBridge1.address, nativeAddressByNetwork('test')).toLowerCase();
      const pegTokenAddress2 = simpleTokenProxyAddress(crossChainBridge2.address, nativeAddressByNetwork('test')).toLowerCase();
      const pegToken1 = new SimpleToken(pegTokenAddress1);
      const pegToken2 = new SimpleToken(pegTokenAddress2);
      await pegToken1.mint(owner, '1000');

      let tx1 = await crossChainBridge1.deposit(pegToken1.address, chainId, recipient, '400'),
        logs1 = tx1.logs;
      assert.equal(logs1[0].event, 'DepositBurned');
      assert.equal(logs1[0].args['fromAddress'].toLowerCase(), owner.toLowerCase());
      assert.equal(logs1[0].args['toAddress'].toLowerCase(), recipient.toLowerCase());
      assert.equal(logs1[0].args['fromToken'].toLowerCase(), pegTokenAddress1);
      assert.equal(logs1[0].args['toToken'].toLowerCase(), pegTokenAddress2);
      assert.equal(logs1[0].args['totalAmount'].toString(10), '400');
      // withdraw native tokens
      const [rawReceipt, receiptHash] = encodeTransactionReceipt(tx1.receipt);
      let tx2 = await crossChainBridge2.withdraw([], rawReceipt, '0x', '0x', {from: recipient}),
        logs2 = tx2.logs;
      // console.log(` ~ Peg-Out gas used: ${tx2.receipt.cumulativeGasUsed}`);
      assert.equal(logs2[0].event, 'WithdrawMinted');
      assert.equal(logs2[0].args['receiptHash'], receiptHash);
      assert.equal(logs2[0].args['fromAddress'].toLowerCase(), owner.toLowerCase());
      assert.equal(logs2[0].args['toAddress'].toLowerCase(), recipient.toLowerCase());
      assert.equal(logs2[0].args['fromToken'].toLowerCase(), pegTokenAddress1);
      assert.equal(logs2[0].args['toToken'].toLowerCase(), pegTokenAddress2);
      assert.equal(logs2[0].args['totalAmount'].toString(10), '400');
      //Check balances
      assert.equal(await pegToken1.symbol(), 'ETH');
      assert.equal(await pegToken1.name(), 'Ethereum');
      assert.equal((await pegToken1.decimals()).toString(10), '18');
      assert.equal(await pegToken2.symbol(), 'ETH');
      assert.equal(await pegToken2.name(), 'Ethereum');
      assert.equal((await pegToken2.decimals()).toString(10), '18');
      const peggedBalance1 = await pegToken1.balanceOf(owner);
      const peggedBalance2 = await pegToken2.balanceOf(recipient);
      assert.equal(peggedBalance1.toString(10), '600');
      assert.equal(peggedBalance2.toString(10), '400');
    });

    it("pegged (of ERC20) to pegged (burn)", async () => {
      // deposit tokens to smart contract (peg-in)
      const pegTokenAddress1 = simpleTokenProxyAddress(crossChainBridge1.address, ankrToken.address).toLowerCase();
      const pegTokenAddress2 = simpleTokenProxyAddress(crossChainBridge2.address, ankrToken.address).toLowerCase()
      const pegToken1 = new SimpleToken(pegTokenAddress1);
      const pegToken2 = new SimpleToken(pegTokenAddress2);
      await pegToken1.mint(owner, '1000');

      let tx1 = await crossChainBridge1.deposit(pegToken1.address, chainId, recipient, '300'),
        logs1 = tx1.logs;
      assert.equal(logs1[0].event, 'DepositBurned');
      assert.equal(logs1[0].args['fromAddress'].toLowerCase(), owner.toLowerCase());
      assert.equal(logs1[0].args['toAddress'].toLowerCase(), recipient.toLowerCase());
      assert.equal(logs1[0].args['fromToken'].toLowerCase(), pegTokenAddress1);
      assert.equal(logs1[0].args['toToken'].toLowerCase(), pegTokenAddress2);
      assert.equal(logs1[0].args['totalAmount'].toString(10), '300');
      // withdraw native tokens
      const [rawReceipt, receiptHash] = encodeTransactionReceipt(tx1.receipt);
      let tx2 = await crossChainBridge2.withdraw([], rawReceipt, '0x', '0x', {from: recipient}),
        logs2 = tx2.logs;
      // console.log(` ~ Peg-Out gas used: ${tx2.receipt.cumulativeGasUsed}`);
      assert.equal(logs2[0].event, 'WithdrawMinted');
      assert.equal(logs2[0].args['receiptHash'], receiptHash);
      assert.equal(logs2[0].args['fromAddress'].toLowerCase(), owner.toLowerCase());
      assert.equal(logs2[0].args['toAddress'].toLowerCase(), recipient.toLowerCase());
      assert.equal(logs2[0].args['fromToken'].toLowerCase(), pegTokenAddress1);
      assert.equal(logs2[0].args['toToken'].toLowerCase(), pegTokenAddress2);
      assert.equal(logs2[0].args['totalAmount'].toString(10), '300');
      //Check balances
      assert.equal(await pegToken1.symbol(), 'ANKR');
      assert.equal(await pegToken1.name(), 'Ankr Network');
      assert.equal((await pegToken1.decimals()).toString(10), '18');
      assert.equal(await pegToken2.symbol(), 'ANKR');
      assert.equal(await pegToken2.name(), 'Ankr Network');
      assert.equal((await pegToken2.decimals()).toString(10), '18');
      const peggedBalance1 = await pegToken1.balanceOf(owner);
      const peggedBalance2 = await pegToken2.balanceOf(recipient);
      assert.equal(peggedBalance1.toString(10), '700');
      assert.equal(peggedBalance2.toString(10), '300');
    });
  });

  describe("deploy pegged contracts on the fly", async () => {

    let tokenFactory, crossChainBridge0, crossChainBridge1, crossChainBridge2, ankrToken, chainId;

    before(async function () {
      chainId = await getFixedChainId();
      // token factory (use TestToken2 that allows minting by anyone)
      tokenFactory = await TestTokenFactory.new();
      // router
      const bridgeRouter = await BridgeRouter.new();
      const basRelayHub0 = await TestRelayHub.new();
      const basRelayHub1 = await TestRelayHub.new();
      const basRelayHub2 = await TestRelayHub.new();
      // bridge
      crossChainBridge0 = await CrossChainBridge.new();
      const {name, symbol} = nameAndSymbolByNetwork('test');
      await crossChainBridge0.initialize(basRelayHub0.address, basRelayHub0.address, tokenFactory.address, bridgeRouter.address, symbol, name);
      crossChainBridge1 = await CrossChainBridge.new();
      await crossChainBridge1.initialize(basRelayHub1.address, basRelayHub1.address, tokenFactory.address, bridgeRouter.address, symbol, name);
      crossChainBridge2 = await CrossChainBridge.new();
      await crossChainBridge2.initialize(basRelayHub2.address, basRelayHub2.address, tokenFactory.address, bridgeRouter.address, symbol, name);
      // tokens
      ankrToken = await SimpleToken.new();
      await ankrToken.initialize(web3.utils.fromAscii('Ankr'), web3.utils.fromAscii('Ankr'), 0, ZERO_ADDRESS, {from: owner});
      await ankrToken.mint(owner, '100000000000000000000');
    });

    it('add allowed contract', async () => {
      (await TestRelayHub.at(await crossChainBridge1.getRelayHub())).enableCrossChainBridge(chainId, crossChainBridge2.address);
      (await TestRelayHub.at(await crossChainBridge2.getRelayHub())).enableCrossChainBridge(chainId, crossChainBridge1.address);
      (await TestRelayHub.at(await crossChainBridge1.getRelayHub())).enableCrossChainBridge(chainId + 1, crossChainBridge0.address);
      (await TestRelayHub.at(await crossChainBridge2.getRelayHub())).enableCrossChainBridge(chainId + 1, crossChainBridge0.address);
    });

    it("warmup pegged tokens", async () => {
      // warmup pegged ethereum
      assert.equal(await crossChainBridge1.isPeggedToken(simpleTokenProxyAddress(crossChainBridge1.address, nativeAddressByNetwork('test'))), false);
      await crossChainBridge1.factoryPeggedToken(chainId + 1, createSimpleTokenMetaData('ETH1', 'Ethereum1', chainId + 1, nativeAddressByNetwork('test')));
      assert.equal(await crossChainBridge1.isPeggedToken(simpleTokenProxyAddress(crossChainBridge1.address, nativeAddressByNetwork('test'))), true);
      // warmup pegged ankr
      assert.equal(await crossChainBridge1.isPeggedToken(simpleTokenProxyAddress(crossChainBridge1.address, ankrToken.address).toLowerCase()), false);
      await crossChainBridge1.factoryPeggedToken(chainId + 1, createSimpleTokenMetaData('ANKR1', 'Ankr Network1', chainId + 1, ankrToken.address));
      assert.equal(await crossChainBridge1.isPeggedToken(simpleTokenProxyAddress(crossChainBridge1.address, ankrToken.address).toLowerCase()), true);
    })

    it("pegged (of native) to pegged (burn)", async () => {
      // deposit tokens to smart contract (peg-in)
      const pegTokenAddress1 = simpleTokenProxyAddress(crossChainBridge1.address, nativeAddressByNetwork('test')).toLowerCase();
      const pegTokenAddress2 = simpleTokenProxyAddress(crossChainBridge2.address, nativeAddressByNetwork('test')).toLowerCase();
      const pegToken1 = new SimpleToken(pegTokenAddress1);
      const pegToken2 = new SimpleToken(pegTokenAddress2);
      await pegToken1.mint(owner, '1000');

      let tx1 = await crossChainBridge1.deposit(pegToken1.address, chainId, recipient, '400'),
        logs1 = tx1.logs;
      assert.equal(logs1[0].event, 'DepositBurned');
      assert.equal(logs1[0].args['fromAddress'].toLowerCase(), owner.toLowerCase());
      assert.equal(logs1[0].args['toAddress'].toLowerCase(), recipient.toLowerCase());
      assert.equal(logs1[0].args['fromToken'].toLowerCase(), pegTokenAddress1);
      assert.equal(logs1[0].args['toToken'].toLowerCase(), pegTokenAddress2);
      assert.equal(logs1[0].args['totalAmount'].toString(10), '400');
      // withdraw native tokens
      const [rawReceipt, receiptHash] = encodeTransactionReceipt(tx1.receipt);
      let tx2 = await crossChainBridge2.withdraw([], rawReceipt, '0x', '0x', {from: recipient}),
        logs2 = tx2.logs;
      // console.log(` ~ Peg-Out gas used: ${tx2.receipt.cumulativeGasUsed}`);
      assert.equal(logs2[0].event, 'WithdrawMinted');
      assert.equal(logs2[0].args['receiptHash'], receiptHash);
      assert.equal(logs2[0].args['fromAddress'].toLowerCase(), owner.toLowerCase());
      assert.equal(logs2[0].args['toAddress'].toLowerCase(), recipient.toLowerCase());
      assert.equal(logs2[0].args['fromToken'].toLowerCase(), pegTokenAddress1);
      assert.equal(logs2[0].args['toToken'].toLowerCase(), pegTokenAddress2);
      assert.equal(logs2[0].args['totalAmount'].toString(10), '400');
      //Check balances
      assert.equal(await pegToken1.symbol(), 'ETH1');
      assert.equal(await pegToken1.name(), 'Ethereum1');
      assert.equal(await pegToken1.decimals(), '18');
      assert.equal(await pegToken2.symbol(), 'ETH1');
      assert.equal(await pegToken2.name(), 'Ethereum1');
      assert.equal(await pegToken2.decimals(), '18');
      const peggedBalance1 = await pegToken1.balanceOf(owner);
      const peggedBalance2 = await pegToken2.balanceOf(recipient);
      assert.equal(peggedBalance1.toString(10), '600');
      assert.equal(peggedBalance2.toString(10), '400');
    });

    it("pegged (of ERC20) to pegged (burn)", async () => {
      // deposit tokens to smart contract (peg-in)
      const pegTokenAddress1 = simpleTokenProxyAddress(crossChainBridge1.address, ankrToken.address).toLowerCase();
      const pegTokenAddress2 = simpleTokenProxyAddress(crossChainBridge2.address, ankrToken.address).toLowerCase()
      const pegToken1 = new SimpleToken(pegTokenAddress1);
      const pegToken2 = new SimpleToken(pegTokenAddress2);
      await pegToken1.mint(owner, '1000');

      let tx1 = await crossChainBridge1.deposit(pegToken1.address, chainId, recipient, '300'),
        logs1 = tx1.logs;
      assert.equal(logs1[0].event, 'DepositBurned');
      assert.equal(logs1[0].args['fromAddress'].toLowerCase(), owner.toLowerCase());
      assert.equal(logs1[0].args['toAddress'].toLowerCase(), recipient.toLowerCase());
      assert.equal(logs1[0].args['fromToken'].toLowerCase(), pegTokenAddress1);
      assert.equal(logs1[0].args['toToken'].toLowerCase(), pegTokenAddress2);
      assert.equal(logs1[0].args['totalAmount'].toString(10), '300');
      // withdraw native tokens
      const [rawReceipt, receiptHash] = encodeTransactionReceipt(tx1.receipt);
      let tx2 = await crossChainBridge2.withdraw([], rawReceipt, '0x', '0x', {from: recipient}),
        logs2 = tx2.logs;
      // console.log(` ~ Peg-Out gas used: ${tx2.receipt.cumulativeGasUsed}`);
      assert.equal(logs2[0].event, 'WithdrawMinted');
      assert.equal(logs2[0].args['receiptHash'], receiptHash);
      assert.equal(logs2[0].args['fromAddress'].toLowerCase(), owner.toLowerCase());
      assert.equal(logs2[0].args['toAddress'].toLowerCase(), recipient.toLowerCase());
      assert.equal(logs2[0].args['fromToken'].toLowerCase(), pegTokenAddress1);
      assert.equal(logs2[0].args['toToken'].toLowerCase(), pegTokenAddress2);
      assert.equal(logs2[0].args['totalAmount'].toString(10), '300');
      //Check balances
      assert.equal(await pegToken1.symbol(), 'ANKR1');
      assert.equal(await pegToken1.name(), 'Ankr Network1');
      assert.equal(await pegToken1.decimals(), '18');
      assert.equal(await pegToken2.symbol(), 'ANKR1');
      assert.equal(await pegToken2.name(), 'Ankr Network1');
      assert.equal(await pegToken2.decimals(), '18');
      const peggedBalance1 = await pegToken1.balanceOf(owner);
      const peggedBalance2 = await pegToken2.balanceOf(recipient);
      assert.equal(peggedBalance1.toString(10), '700');
      assert.equal(peggedBalance2.toString(10), '300');
    });
  });

  async function runTokenTestSuite(token, params) {
    const {shouldBeName, shouldBeDecimals, shouldBeSymbol} = params;
    // borrowed and adapted from https://github.com/ConsenSys/Tokens/blob/master/test/eip20/eip20.js
    const name = await token.name.call();
    assert.strictEqual(name, shouldBeName);
    const decimals = await token.decimals.call();
    assert.strictEqual(decimals.toNumber(), shouldBeDecimals);
    const symbol = await token.symbol.call();
    assert.strictEqual(symbol, shouldBeSymbol);

    // TRANSFERS
    // normal transfers without approvals
    // pre-requirement: accounts[0] must have 10000 tokens
    const balanceBefore = await token.balanceOf.call(accounts[0]);
    assert.strictEqual(balanceBefore.toNumber(), 10000);

    // 'transfers: ether transfer should be reversed.'
    {
      await expectError(web3.eth.sendTransaction({
        from: accounts[0],
        to: token.address,
        value: web3.utils.toWei('10', 'Ether')
      }));

      const balanceAfter = await token.balanceOf.call(accounts[0]);
      assert.strictEqual(balanceAfter.toNumber(), 10000);
    }

    // 'transfers: should transfer 10000 to accounts[1] with accounts[0] having 10000'
    {
      await token.transfer(accounts[1], 10000, {from: accounts[0]});
      const balance = await token.balanceOf.call(accounts[1]);
      assert.strictEqual(balance.toNumber(), 10000);
      await token.transfer(accounts[0], 10000, {from: accounts[1]});
    }

    // 'transfers: should fail when trying to transfer 10001 to accounts[1] with accounts[0] having 10000'
    {
      await expectError(token.transfer.call(accounts[1], 10001, {from: accounts[0]}));
    }

    // 'transfers: should handle zero-transfers normally'
    {
      assert(await token.transfer.call(accounts[1], 0, {from: accounts[0]}), 'zero-transfer has failed');
      await token.transfer(accounts[1], 0, {from: accounts[0]});
    }

    // APPROVALS
    // 'approvals: msg.sender should approve 100 to accounts[1]'
    {
      await token.approve(accounts[1], 100, {from: accounts[0]});
      const allowance = await token.allowance.call(accounts[0], accounts[1]);
      assert.strictEqual(allowance.toNumber(), 100);
    }

    // 'approvals: msg.sender approves accounts[1] of 100 & withdraws 20 once.'
    {
      const balance0 = await token.balanceOf.call(accounts[0]);
      assert.strictEqual(balance0.toNumber(), 10000);

      await token.approve(accounts[1], 100, {from: accounts[0]}); // 100
      const balance2 = await token.balanceOf.call(accounts[2]);
      assert.strictEqual(balance2.toNumber(), 0, 'balance2 not correct');

      await token.transferFrom.call(accounts[0], accounts[2], 20, {from: accounts[1]});
      await token.allowance.call(accounts[0], accounts[1]);
      await token.transferFrom(accounts[0], accounts[2], 20, {from: accounts[1]}); // -20
      const allowance01 = await token.allowance.call(accounts[0], accounts[1]);
      assert.strictEqual(allowance01.toNumber(), 80); // =80

      const balance22 = await token.balanceOf.call(accounts[2]);
      assert.strictEqual(balance22.toNumber(), 20);

      const balance02 = await token.balanceOf.call(accounts[0]);
      assert.strictEqual(balance02.toNumber(), 9980);
      await token.transfer(accounts[0], 20, {from: accounts[2]});
    }

    // 'approvals: msg.sender approves accounts[1] of 100 & withdraws 20 twice.'
    {
      await token.approve(accounts[1], 100, {from: accounts[0]});
      const allowance01 = await token.allowance.call(accounts[0], accounts[1]);
      assert.strictEqual(allowance01.toNumber(), 100);

      await token.transferFrom(accounts[0], accounts[2], 20, {from: accounts[1]});
      const allowance012 = await token.allowance.call(accounts[0], accounts[1]);
      assert.strictEqual(allowance012.toNumber(), 80);

      const balance2 = await token.balanceOf.call(accounts[2]);
      assert.strictEqual(balance2.toNumber(), 20);

      const balance0 = await token.balanceOf.call(accounts[0]);
      assert.strictEqual(balance0.toNumber(), 9980);

      // FIRST tx done.
      // onto next.
      await token.transferFrom(accounts[0], accounts[2], 20, {from: accounts[1]});
      const allowance013 = await token.allowance.call(accounts[0], accounts[1]);
      assert.strictEqual(allowance013.toNumber(), 60);

      const balance22 = await token.balanceOf.call(accounts[2]);
      assert.strictEqual(balance22.toNumber(), 40);

      const balance02 = await token.balanceOf.call(accounts[0]);
      assert.strictEqual(balance02.toNumber(), 9960);

      await token.transfer(accounts[0], 40, {from: accounts[2]});
    }

    // 'approvals: msg.sender approves accounts[1] of 100 & withdraws 50 & 60 (2nd tx should fail)'
    {
      await token.approve(accounts[1], 100, {from: accounts[0]});
      const allowance01 = await token.allowance.call(accounts[0], accounts[1]);
      assert.strictEqual(allowance01.toNumber(), 100);

      await token.transferFrom(accounts[0], accounts[2], 50, {from: accounts[1]});
      const allowance012 = await token.allowance.call(accounts[0], accounts[1]);
      assert.strictEqual(allowance012.toNumber(), 50);

      const balance2 = await token.balanceOf.call(accounts[2]);
      assert.strictEqual(balance2.toNumber(), 50);

      const balance0 = await token.balanceOf.call(accounts[0]);
      assert.strictEqual(balance0.toNumber(), 9950);

      // FIRST tx done.
      // onto next.
      await expectError(token.transferFrom.call(accounts[0], accounts[2], 60, {from: accounts[1]}));
      await expectError(token.transferFrom(accounts[0], accounts[2], 60, {from: accounts[1]}));

      await token.transfer(accounts[0], 50, {from: accounts[2]});
    }

    // 'approvals: attempt withdrawal from account with no allowance (should fail)'
    {
      await token.approve(accounts[1], 0, {from: accounts[0]});
      await expectError(token.transferFrom.call(accounts[0], accounts[2], 60, {from: accounts[1]}));
    }

    // 'approvals: allow accounts[1] 100 to withdraw from accounts[0]. Withdraw 60 and then approve 0 & attempt transfer.'
    {
      await token.approve(accounts[1], 100, {from: accounts[0]});
      await token.transferFrom(accounts[0], accounts[2], 60, {from: accounts[1]});
      await token.approve(accounts[1], 0, {from: accounts[0]});
      await expectError(token.transferFrom.call(accounts[0], accounts[2], 10, {from: accounts[1]}));
      await token.transfer(accounts[0], 60, {from: accounts[2]});
    }

    // 'approvals: approve max (2^256 - 1)'
    {
      await token.approve(accounts[1], '115792089237316195423570985008687907853269984665640564039457584007913129639935', {from: accounts[0]});
      const allowance = await token.allowance(accounts[0], accounts[1]);
      assert.equal(allowance.toString(), '115792089237316195423570985008687907853269984665640564039457584007913129639935');
      await token.approve(accounts[1], 0, {from: accounts[0]});
    }

    // 'approvals: msg.sender approves accounts[1] of max (2^256 - 1) & withdraws 20'
    {
      const balance0 = await token.balanceOf.call(accounts[0]);
      assert.strictEqual(balance0.toNumber(), 10000);

      const max = '115792089237316195423570985008687907853269984665640564039457584007913129639935';
      await token.approve(accounts[1], max, {from: accounts[0]});
      const balance2 = await token.balanceOf.call(accounts[2]);
      assert.strictEqual(balance2.toNumber(), 0, 'balance2 not correct');

      await token.transferFrom(accounts[0], accounts[2], 20, {from: accounts[1]});
      const allowance01 = await token.allowance.call(accounts[0], accounts[1]);
      assert.equal(allowance01.toString(), '115792089237316195423570985008687907853269984665640564039457584007913129639915');

      const balance22 = await token.balanceOf.call(accounts[2]);
      assert.strictEqual(balance22.toNumber(), 20);

      const balance02 = await token.balanceOf.call(accounts[0]);
      assert.strictEqual(balance02.toNumber(), 9980);
      await token.transfer(accounts[0], 20, {from: accounts[2]});
    }

    // 'events: should fire Transfer event properly'
    {
      const res = await token.transfer(accounts[1], '2666', {from: accounts[0]});
      const transferLog = res.logs.find(element => element.event.match('Transfer'));
      assert.strictEqual(transferLog.args.from, accounts[0]);
      assert.strictEqual(transferLog.args.to, accounts[1]);
      assert.strictEqual(transferLog.args.value.toString(), '2666');
      await token.transfer(accounts[0], '2666', {from: accounts[1]});
    }

    // 'events: should fire Transfer event normally on a zero transfer'
    {
      const res = await token.transfer(accounts[1], '0', {from: accounts[0]});
      const transferLog = res.logs.find(element => element.event.match('Transfer'));
      assert.strictEqual(transferLog.args.from, accounts[0]);
      assert.strictEqual(transferLog.args.to, accounts[1]);
      assert.strictEqual(transferLog.args.value.toString(), '0');
    }

    // 'events: should fire Approval event properly'
    {
      const res = await token.approve(accounts[1], '2666', {from: accounts[0]});
      const approvalLog = res.logs.find(element => element.event.match('Approval'));
      assert.strictEqual(approvalLog.args.owner, accounts[0]);
      assert.strictEqual(approvalLog.args.spender, accounts[1]);
      assert.strictEqual(approvalLog.args.value.toString(), '2666');
    }
  }
});