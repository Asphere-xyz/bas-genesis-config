/** @var artifacts {Array} */
/** @var web3 {Web3} */
/** @function contract */
/** @function it */
/** @function before */
/** @var assert */

const {newMockContract, expectError, extractTxCost, waitForNextEpoch} = require("./helper");

contract("Staking", async (accounts) => {
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
    await stakingPool.stake(validator1, {from: staker1, value: '1000000000000000000'}); // 1.0
    assert.equal((await stakingPool.getStakedAmount(validator1, staker1)).toString(), '1000000000000000000');
    await waitForNextEpoch(parlia);
    await parlia.deposit(validator1, {value: '10000000000000000'}); // 0.01
    await waitForNextEpoch(parlia);
    console.log(`Validator Pool: ${(await stakingPool.getValidatorPool(validator1))}`)
    console.log(`Ratio: ${(await stakingPool.getRatio(validator1)).toString()}`)
    assert.equal((await stakingPool.getStakedAmount(validator1, staker1)).toString(), '1010000000000000000');
    let res = await stakingPool.unstake(validator1, '1010000000000000000'); // 1.01
    assert.equal(res.logs[0].args.validator, validator1)
    assert.equal(res.logs[0].args.staker, staker1)
    assert.equal(res.logs[0].args.amount.toString(), '1010000000000000000')
    await waitForNextEpoch(parlia);
    res = await stakingPool.claim(validator1, {from: staker1});
    assert.equal(res.logs[0].args.validator, validator1)
    assert.equal(res.logs[0].args.staker, staker1)
    assert.equal(res.logs[0].args.amount.toString(), '1010000000000000000')
  })
});
