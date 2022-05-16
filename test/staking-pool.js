/** @var artifacts {Array} */
/** @var web3 {Web3} */
/** @function contract */
/** @function it */
/** @function before */
/** @var assert */

const {newMockContract, waitForNextEpoch} = require("./helper");

contract("StakingPool", async (accounts) => {
  const [owner, staker1, staker2, validator1] = accounts
  it("empty delegator claim should work", async () => {
    const {parlia} = await newMockContract(owner, {epochBlockInterval: '50'})
    await parlia.addValidator(validator1);
    await parlia.claimDelegatorFee(validator1, {from: staker1});
  })
  it("staker can do simple delegation", async () => {
    const {parlia, stakingPool} = await newMockContract(owner, {epochBlockInterval: '50'})
    await parlia.addValidator(validator1);
    let res = await stakingPool.stake(validator1, {from: staker1, value: '1000000000000000000'}); // 1.0
    assert.equal(res.logs[0].args.validator, validator1);
    assert.equal(res.logs[0].args.staker, staker1);
    assert.equal(res.logs[0].args.amount.toString(), '1000000000000000000');
    res = await stakingPool.stake(validator1, {from: staker1, value: '1000000000000000000'}); // 1.0
    assert.equal(res.logs[0].args.validator, validator1);
    assert.equal(res.logs[0].args.staker, staker1);
    assert.equal(res.logs[0].args.amount.toString(), '1000000000000000000');
    res = await stakingPool.stake(validator1, {from: staker2, value: '1000000000000000000'});
    assert.equal(res.logs[0].args.validator, validator1);
    assert.equal(res.logs[0].args.staker, staker2);
    assert.equal(res.logs[0].args.amount.toString(), '1000000000000000000');
    assert.equal((await stakingPool.getStakedAmount(validator1, staker1)).toString(10), '2000000000000000000');
    assert.equal((await stakingPool.getStakedAmount(validator1, staker2)).toString(10), '1000000000000000000');
  })
  it("staker can claim his rewards", async () => {
    const {parlia, stakingPool} = await newMockContract(owner, {epochBlockInterval: '10'})
    await parlia.addValidator(validator1);
    await stakingPool.stake(validator1, {from: staker1, value: '50000000000000000000'}); // 50.0
    assert.equal((await stakingPool.getStakedAmount(validator1, staker1)).toString(), '50000000000000000000');
    await waitForNextEpoch(parlia);
    await parlia.deposit(validator1, {value: '1010000000000000000'}); // 10.1
    await waitForNextEpoch(parlia);
    // console.log(`Validator Pool: ${JSON.stringify(await stakingPool.getValidatorPool(validator1), null, 2)}`)
    // console.log(`Ratio: ${(await stakingPool.getRatio(validator1)).toString()}`)
    assert.equal((await stakingPool.getStakedAmount(validator1, staker1)).toString(), '51009999999999999964');
    let res = await stakingPool.unstake(validator1, '50000000000000000000', {from: staker1});
    assert.equal(res.logs[0].args.validator, validator1)
    assert.equal(res.logs[0].args.staker, staker1)
    assert.equal(res.logs[0].args.amount.toString(), '50000000000000000000')
    await waitForNextEpoch(parlia);
    res = await stakingPool.claim(validator1, {from: staker1});
    assert.equal(res.logs[0].args.validator, validator1)
    assert.equal(res.logs[0].args.staker, staker1)
    assert.equal(res.logs[0].args.amount.toString(), '50000000000000000000')
    // console.log(`Validator Pool: ${JSON.stringify(await stakingPool.getValidatorPool(validator1), null, 2)}`)
    // console.log(`Ratio: ${(await stakingPool.getRatio(validator1)).toString()}`)
    // rest can't be claimed due to rounding problem (now can, because we have increased the precision)
    assert.equal((await stakingPool.getStakedAmount(validator1, staker1)).toString(), '1009999999999999999');
  })
});
