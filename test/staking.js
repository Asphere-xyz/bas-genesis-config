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
  const [staker1, staker2, staker3, validator1, validator2, validator3] = accounts
  it("delegation should work", async () => {
    const parlia = await FakeStaking.new();
    await parlia.addValidator(validator1);
    await parlia.addValidator(validator2);
    await parlia.addValidator(validator3);
    const res = await parlia.delegate(validator1, {from: staker1, value: '1000000000000000000'});
    console.log(res.logs)
    let result = await parlia.getValidatorDelegation(validator1, staker1);
    assert.equal(result.delegatedAmount.toString(), '1000000000000000000')
    assert.equal(result.unstakeBlockedBefore.toString(), '0')
    assert.equal(result.pendingUndelegate.toString(), '0')
    await parlia.delegate(validator1, {from: staker1, value: '1000000000000000000'});
    result = await parlia.getValidatorDelegation(validator1, staker1);
    assert.equal(result.delegatedAmount.toString(), '2000000000000000000')
    assert.equal(result.unstakeBlockedBefore.toString(), '0')
    assert.equal(result.pendingUndelegate.toString(), '0')
  });
});
