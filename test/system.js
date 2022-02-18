/** @var artifacts {Array} */
/** @var web3 {Web3} */
/** @function contract */
/** @function it */
/** @function before */
/** @var assert */

const {newMockContract} = require('./helper')
const BigNumber = require('bignumber.js');

contract("SystemReward", async (accounts) => {
  const [owner, treasury] = accounts
  it("system fee is well calculated", async () => {
    const {systemReward} = await newMockContract(owner, {systemTreasury: treasury,})
    // send 1 ether
    await web3.eth.sendTransaction({from: owner, to: systemReward.address, value: '1000000000000000000'}); // 1 ether
    // balance and state should be 1
    assert.equal((await web3.eth.getBalance(systemReward.address)).toString(), '1000000000000000000')
    assert.equal((await systemReward.getSystemFee()).toString(), '1000000000000000000')
    // send 1 ether
    await web3.eth.sendTransaction({from: owner, to: systemReward.address, value: '1000000000000000000'}); // 1 ether
    // balance and state should be 2
    assert.equal((await web3.eth.getBalance(systemReward.address)).toString(), '2000000000000000000')
    assert.equal((await systemReward.getSystemFee()).toString(), '2000000000000000000')
    // claim to treasury
    await systemReward.claimSystemFee({from: treasury});
    // balance and state should be 0
    assert.equal((await web3.eth.getBalance(systemReward.address)).toString(), '0')
    assert.equal((await systemReward.getSystemFee()).toString(), '0')
  })
  it("system fee is auto claimable after 50 ether", async () => {
    const {systemReward} = await newMockContract(owner, {systemTreasury: treasury,})
    const initialBalance = new BigNumber((await web3.eth.getBalance(treasury)).toString());
    // send 49 ether
    await web3.eth.sendTransaction({from: owner, to: systemReward.address, value: '49000000000000000000'}); // 49 ether
    // balance shouldn't change
    assert.equal((await web3.eth.getBalance(treasury)).toString(), initialBalance.toString(10))
    assert.equal((await systemReward.getSystemFee()).toString(), '49000000000000000000')
    // send 2 ether more
    await web3.eth.sendTransaction({from: owner, to: systemReward.address, value: '2000000000000000000'}); // 2 ether
    // fee is not claimable anymore
    assert.equal((await web3.eth.getBalance(treasury)).toString(), initialBalance.plus('51000000000000000000').toString(10))
    assert.equal((await systemReward.getSystemFee()).toString(), '0')
  })
});
