/** @var artifacts {Array} */
/** @var web3 {Web3} */
/** @function contract */
/** @function it */
/** @function before */
/** @var assert */

const Deployer = artifacts.require("Deployer");
const Governance = artifacts.require("Governance");
const Parlia = artifacts.require("Parlia");
const FakeStaking = artifacts.require("FakeStaking");

contract("Staking", async (accounts) => {
  const [staker1, staker2, staker3, validator1, validator2, validator3, validator4, validator5] = accounts
  it("simple delegation should work", async () => {
    const parlia = await FakeStaking.new();
    await parlia.addValidator(validator1);
    // staker 1
    const res = await parlia.delegate(validator1, {from: staker1, value: '1000000000000000000'}); // 1.0
    assert.equal(res.logs[0].args.validator, validator1);
    assert.equal(res.logs[0].args.from, staker1);
    assert.equal(res.logs[0].args.amount.toString(), '1000000000000000000');
    let result = await parlia.getValidatorDelegation(validator1, staker1);
    assert.equal(result.delegatedAmount.toString(), '1000000000000000000')
    assert.equal(result.unstakeBlockedBefore.toString(), '0')
    assert.equal(result.pendingUndelegate.toString(), '0')
    await parlia.delegate(validator1, {from: staker2, value: '1000000000000000000'});
    result = await parlia.getValidatorDelegation(validator1, staker2);
    assert.equal(result.delegatedAmount.toString(), '1000000000000000000')
    assert.equal(result.unstakeBlockedBefore.toString(), '0')
    assert.equal(result.pendingUndelegate.toString(), '0')
    result = await parlia.getValidatorDelegations(validator1);
    assert.equal(result.delegated.toString(), '2000000000000000000')
    assert.equal(result.status.toString(), '1')
  })
  it("active validator order", async () => {
    const parlia = await FakeStaking.new();
    await parlia.addValidator(validator1); // 0x821aEa9a577a9b44299B9c15c88cf3087F3b5544
    await parlia.addValidator(validator2); // 0x0d1d4e623D10F9FBA5Db95830F7d3839406C6AF2
    await parlia.addValidator(validator3); // 0x2932b7A2355D6fecc4b5c0B6BD44cC31df247a2e
    await parlia.addValidator(validator4); // 0x2191eF87E392377ec08E7c08Eb105Ef5448eCED5
    await parlia.addValidator(validator5); // 0x0F4F2Ac550A1b4e2280d04c21cEa7EBD822934b5
    // delegate
    await parlia.delegate(validator1, {from: staker1, value: '2000000000000000000'}); // 2.0
    await parlia.delegate(validator2, {from: staker2, value: '1500000000000000000'}); // 1.5
    await parlia.delegate(validator3, {from: staker3, value: '1000000000000000000'}); // 1.0
    // make sure validators are sorted
    assert.deepEqual(Array.from(await parlia.getValidators()), [
      validator1,
      validator2,
      validator3,
    ])
    // delegate more to validator 4
    await parlia.delegate(validator4, {from: staker3, value: '3000000000000000000'}); // 3.0
    // check new active set
    assert.deepEqual(Array.from(await parlia.getValidators()), [
      validator4,
      validator1,
      validator2,
    ])
  });
});
