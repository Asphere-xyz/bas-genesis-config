/** @var artifacts {Array} */
/** @var web3 {Web3} */
/** @function contract */
/** @function it */
/** @function before */
/** @var assert */

const {newMockContract, expectError} = require('./helper')
const BigNumber = require('bignumber.js');

contract("SystemReward", async (accounts) => {
  const [owner, treasury, governance] = accounts
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
  it("system reward can be distributed using shares", async () => {
    const {systemReward} = await newMockContract(owner, {systemTreasury: treasury,})
    let distributionShares = await systemReward.getDistributionShares();
    assert.equal(distributionShares[0].account, treasury);
    assert.equal(distributionShares[0].share, '10000'); // 100%
    await web3.eth.sendTransaction({from: owner, to: systemReward.address, value: '49000000000000000000'}); // 49 ether
    const res1 = await systemReward.claimSystemFee();
    assert.equal(res1.logs[0].event, 'FeeClaimed');
    assert.equal(res1.logs[0].args.account, treasury);
    assert.equal(res1.logs[0].args.amount.toString(), '49000000000000000000');
    // not lets change distribution scheme (50%,25%,25%)
    const res2 = await systemReward.updateDistributionShare([treasury, owner, governance], ['5000', '2500', '2500']);
    distributionShares = await systemReward.getDistributionShares();
    assert.equal(distributionShares[0].account, treasury);
    assert.equal(distributionShares[0].share, '5000');
    assert.equal(distributionShares[1].account, owner);
    assert.equal(distributionShares[1].share, '2500');
    assert.equal(distributionShares[2].account, governance);
    assert.equal(distributionShares[2].share, '2500');
    assert.equal(res2.logs[0].event, 'DistributionShareChanged');
    assert.equal(res2.logs[0].args.account, treasury);
    assert.equal(res2.logs[0].args.share, '5000');
    assert.equal(res2.logs[1].event, 'DistributionShareChanged');
    assert.equal(res2.logs[1].args.account, owner);
    assert.equal(res2.logs[1].args.share, '2500');
    assert.equal(res2.logs[2].event, 'DistributionShareChanged');
    assert.equal(res2.logs[2].args.account, governance);
    assert.equal(res2.logs[2].args.share, '2500');
    await web3.eth.sendTransaction({from: owner, to: systemReward.address, value: '49000000000000000000'}); // 49 ether
    const res3 = await systemReward.claimSystemFee();
    assert.equal(res3.logs[0].event, 'FeeClaimed');
    assert.equal(res3.logs[0].args.account, treasury);
    assert.equal(res3.logs[0].args.amount.toString(), '24500000000000000000'); // 24.50 (50%)
    assert.equal(res3.logs[1].event, 'FeeClaimed');
    assert.equal(res3.logs[1].args.account, owner);
    assert.equal(res3.logs[1].args.amount.toString(), '12250000000000000000'); // 12.25 (25%)
    assert.equal(res3.logs[2].event, 'FeeClaimed');
    assert.equal(res3.logs[2].args.account, governance);
    assert.equal(res3.logs[2].args.amount.toString(), '12250000000000000000'); // 12.25 (25%)
  });
  it("system reward dust is well calculated", async () => {
    const {systemReward} = await newMockContract(owner, {
      systemTreasury: {
        [treasury]: '1000', // 10%
        [owner]: '9000' // 90%
      }
    })
    await web3.eth.sendTransaction({from: owner, to: systemReward.address, value: '12345'}); // 0.000000000000012345 ether
    const res1 = await systemReward.claimSystemFee();
    assert.equal(res1.logs[0].event, 'FeeClaimed');
    assert.equal(res1.logs[0].args.account, treasury);
    assert.equal(res1.logs[0].args.amount.toString(), '1234');
    assert.equal(res1.logs[1].event, 'FeeClaimed');
    assert.equal(res1.logs[1].args.account, owner);
    assert.equal(res1.logs[1].args.amount.toString(), '11110');
    const dust = await systemReward.getSystemFee();
    assert.equal(dust.toString(), '1');
  });
  it("decrease distribution schemes change array size", async () => {
    const {systemReward} = await newMockContract(owner, {
      systemTreasury: {
        [treasury]: '1000', // 10%
        [owner]: '9000' // 90%
      }
    })
    let distributionShares = await systemReward.getDistributionShares();
    assert.equal(distributionShares.length, 2);
    assert.equal(distributionShares[0].account, treasury);
    assert.equal(distributionShares[0].share, '1000');
    assert.equal(distributionShares[1].account, owner);
    assert.equal(distributionShares[1].share, '9000');
    await systemReward.updateDistributionShare([treasury], ['10000']);
    distributionShares = await systemReward.getDistributionShares();
    assert.equal(distributionShares.length, 1);
    assert.equal(distributionShares[0].account, treasury);
    assert.equal(distributionShares[0].share, '10000');
  });
  it("share distribution must be valid", async () => {
    const {systemReward} = await newMockContract(owner)
    await expectError(systemReward.updateDistributionShare([], []), 'bad share distribution');
    await expectError(systemReward.updateDistributionShare([treasury], ['0']), 'bad share distribution');
    await expectError(systemReward.updateDistributionShare([treasury], ['10001']), 'bad share distribution');
    await expectError(systemReward.updateDistributionShare([treasury], ['1']), 'bad share distribution');
    await expectError(systemReward.updateDistributionShare([treasury], ['9999']), 'bad share distribution');
  });
});
