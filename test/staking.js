/** @var artifacts {Array} */
/** @var web3 {Web3} */
/** @function contract */
/** @function it */
/** @function before */
/** @var assert */

const {newMockContract, expectError, extractTxCost, waitForNextEpoch} = require("./helper");
const BigNumber = require('bignumber.js');

const claimDelegatorFeeAndCheck = async (parlia, validator, staker, shouldBeAmount) => {
  let validatorStakingFee = await parlia.getDelegatorFee(validator, staker)
  assert.equal(validatorStakingFee.toString(10), shouldBeAmount)
  let delegatorBalanceBefore = new BigNumber(await web3.eth.getBalance(staker));
  let {logs, txCost} = extractTxCost(await parlia.claimDelegatorFee(validator, {from: staker}));
  assert.equal(logs[0].event, 'Claimed')
  assert.equal(logs[0].args.amount, shouldBeAmount)
  let delegatorBalanceAfter = new BigNumber(await web3.eth.getBalance(staker));
  assert.equal(delegatorBalanceAfter.minus(delegatorBalanceBefore).plus(txCost).toString(10), shouldBeAmount)
}

const claimValidatorFeeAndCheck = async (parlia, validator, shouldBeAmount) => {
  let validatorStakingFee = await parlia.getValidatorFee(validator)
  assert.equal(validatorStakingFee.toString(10), shouldBeAmount)
  let validatorOwnerBalanceBefore = new BigNumber(await web3.eth.getBalance(validator));
  let {txCost} = extractTxCost(await parlia.claimValidatorFee(validator, {from: validator}))
  let validatorOwnerBalanceAfter = new BigNumber(await web3.eth.getBalance(validator));
  assert.equal(validatorOwnerBalanceAfter.minus(validatorOwnerBalanceBefore).plus(txCost).toString(10), shouldBeAmount);
}

contract("Staking", async (accounts) => {
  const [owner, staker1, staker2, staker3, validator1, validator2, validator3, validator4, validator5] = accounts
  it("staker can do simple delegation", async () => {
    // 1 transaction = 1 block, current epoch length is 10 blocks
    const {parlia} = await newMockContract(owner, {epochBlockInterval: '50'})
    await parlia.addValidator(validator1);
    let result = await parlia.getValidatorDelegation(validator1, staker1);
    assert.equal(result.delegatedAmount.toString(), '0')
    let res = await parlia.delegate(validator1, {from: staker1, value: '1000000000000000000'}); // 1.0
    assert.equal(res.logs[0].args.validator, validator1);
    assert.equal(res.logs[0].args.staker, staker1);
    assert.equal(res.logs[0].args.amount.toString(), '1000000000000000000');
    result = await parlia.getValidatorDelegation(validator1, staker1);
    assert.equal(result.delegatedAmount.toString(), '1000000000000000000')
    res = await parlia.delegate(validator1, {from: staker2, value: '1000000000000000000'});
    assert.equal(res.logs[0].args.validator, validator1);
    assert.equal(res.logs[0].args.staker, staker2);
    assert.equal(res.logs[0].args.amount.toString(), '1000000000000000000');
    result = await parlia.getValidatorDelegation(validator1, staker2);
    assert.equal(result.delegatedAmount.toString(), '1000000000000000000')
    // check validator status
    result = await parlia.getValidatorStatus(validator1);
    assert.equal(result.totalDelegated.toString(), '2000000000000000000')
    assert.equal(result.status.toString(), '1')
  })
  it("delegate after committed delegation should increase delegated amount", async () => {
    const {parlia} = await newMockContract(owner)
    await parlia.addValidator(validator1);
    await parlia.delegate(validator1, {from: staker1, value: '1000000000000000000'}); // 1.0
    let result = await parlia.getValidatorDelegation(validator1, staker1);
    assert.equal(result.delegatedAmount.toString(), '1000000000000000000')
    await waitForNextEpoch(parlia);
    await parlia.delegate(validator1, {from: staker1, value: '1000000000000000000'}); // 1.0
    result = await parlia.getValidatorDelegation(validator1, staker1);
    assert.equal(result.delegatedAmount.toString(), '2000000000000000000')
  });
  it("user should be able undelegate after undelegate", async () => {
    const {parlia} = await newMockContract(owner)
    await parlia.addValidator(validator1);
    await parlia.delegate(validator1, {from: staker1, value: '3000000000000000000'}); // 3.0
    await waitForNextEpoch(parlia);
    await parlia.undelegate(validator1, '1000000000000000000', {from: staker1}); // 1.0
    await parlia.undelegate(validator1, '1000000000000000000', {from: staker1}); // 1.0
    await waitForNextEpoch(parlia);
    await parlia.undelegate(validator1, '1000000000000000000', {from: staker1}); // 1.0
    let result = await parlia.getValidatorStatus(validator1);
    assert.equal(result.totalDelegated.toString(), '0')
    await waitForNextEpoch(parlia);
    await claimDelegatorFeeAndCheck(parlia, validator1, staker1, '3000000000000000000')
  });
  it("undelegate should work on existing delegation", async () => {
    const {parlia} = await newMockContract(owner)
    await parlia.addValidator(validator1);
    await parlia.addValidator(validator2);
    await parlia.delegate(validator1, {from: staker1, value: '1000000000000000000'}); // +1.0
    assert.deepEqual(Array.from(await parlia.getValidators()), [validator1, validator2])
    await parlia.delegate(validator2, {from: staker2, value: '2000000000000000000'}); // +2.0
    assert.deepEqual(Array.from(await parlia.getValidators()), [validator2, validator1])
    assert.equal((await parlia.getValidatorStatus(validator1)).totalDelegated.toString(), '1000000000000000000')
    assert.equal((await parlia.getValidatorStatus(validator2)).totalDelegated.toString(), '2000000000000000000')
    await expectError(parlia.undelegate(validator2, '1', {from: staker2}), 'Staking: amount is too low');
    await expectError(parlia.undelegate(validator2, '1000000000000000001', {from: staker2}), 'Staking: amount have a remainder');
    let res = await parlia.undelegate(validator2, '1000000000000000000', {from: staker2});
    assert.equal(res.logs[0].args.validator, validator2);
    assert.equal(res.logs[0].args.staker, staker2);
    assert.equal(res.logs[0].args.amount.toString(), '1000000000000000000');
    assert.equal((await parlia.getValidatorStatus(validator1)).totalDelegated.toString(), '1000000000000000000')
    assert.equal((await parlia.getValidatorStatus(validator2)).totalDelegated.toString(), '1000000000000000000')
    assert.deepEqual(Array.from(await parlia.getValidators()), [validator1, validator2])
    assert.equal((await parlia.getValidatorDelegation(validator2, staker2)).delegatedAmount.toString(), '1000000000000000000')
    await parlia.undelegate(validator2, '1000000000000000000', {from: staker2})
    assert.equal((await parlia.getValidatorDelegation(validator2, staker2)).delegatedAmount.toString(), '0')
    await waitForNextEpoch(parlia);
    await claimDelegatorFeeAndCheck(parlia, validator1, staker1, '0')
    await claimDelegatorFeeAndCheck(parlia, validator2, staker2, '2000000000000000000')
  });
  it("staker can't undelegate more than delegated", async () => {
    const {parlia} = await newMockContract(owner)
    await parlia.addValidator(validator1);
    // delegate 6 tokens to the validator
    await parlia.delegate(validator1, {from: staker1, value: '1000000000000000000'}); // +1.0
    assert.equal((await parlia.getValidatorDelegation(validator1, staker1)).delegatedAmount.toString(), '1000000000000000000')
    assert.equal((await parlia.getValidatorStatus(validator1)).totalDelegated.toString(), '1000000000000000000')
    await parlia.delegate(validator1, {from: staker1, value: '2000000000000000000'}); // +2.0
    assert.equal((await parlia.getValidatorDelegation(validator1, staker1)).delegatedAmount.toString(), '3000000000000000000')
    assert.equal((await parlia.getValidatorStatus(validator1)).totalDelegated.toString(), '3000000000000000000')
    await parlia.delegate(validator1, {from: staker1, value: '3000000000000000000'}); // +3.0
    assert.equal((await parlia.getValidatorDelegation(validator1, staker1)).delegatedAmount.toString(), '6000000000000000000')
    assert.equal((await parlia.getValidatorStatus(validator1)).totalDelegated.toString(), '6000000000000000000')
    // undelegate first 5
    await parlia.undelegate(validator1, '5000000000000000000', {from: staker1}); // -5.0
    assert.equal((await parlia.getValidatorDelegation(validator1, staker1)).delegatedAmount.toString(), '1000000000000000000')
    // undelegate second 2
    await expectError(parlia.undelegate(validator1, '2000000000000000000', {from: staker1}), 'Staking: insufficient balance') // -2.0
    assert.equal((await parlia.getValidatorDelegation(validator1, staker1)).delegatedAmount.toString(), '1000000000000000000')
    assert.equal((await parlia.getValidatorStatus(validator1)).totalDelegated.toString(), '1000000000000000000')
    // undelegate last 1
    await parlia.undelegate(validator1, '1000000000000000000', {from: staker1}); // -1.0
    assert.equal((await parlia.getValidatorDelegation(validator1, staker1)).delegatedAmount.toString(), '0')
    assert.equal((await parlia.getValidatorStatus(validator1)).totalDelegated.toString(), '0')
    await waitForNextEpoch(parlia);
    await claimDelegatorFeeAndCheck(parlia, validator1, staker1, '6000000000000000000')
  })
  it("active validator set depends on staked amount", async () => {
    const {parlia} = await newMockContract(owner)
    // check current epochs
    await parlia.addValidator(validator1); // 0x821aEa9a577a9b44299B9c15c88cf3087F3b5544
    await parlia.addValidator(validator2); // 0x0d1d4e623D10F9FBA5Db95830F7d3839406C6AF2
    await parlia.addValidator(validator3); // 0x2932b7A2355D6fecc4b5c0B6BD44cC31df247a2e
    await parlia.addValidator(validator4); // 0x2191eF87E392377ec08E7c08Eb105Ef5448eCED5
    await parlia.addValidator(validator5); // 0x0F4F2Ac550A1b4e2280d04c21cEa7EBD822934b5
    // delegate
    await parlia.delegate(validator1, {from: staker1, value: '3000000000000000000'}); // 3.0
    await parlia.delegate(validator2, {from: staker2, value: '2000000000000000000'}); // 2.0
    await parlia.delegate(validator3, {from: staker3, value: '1000000000000000000'}); // 1.0
    // make sure validators are sorted
    assert.deepEqual(Array.from(await parlia.getValidators()), [
      validator1,
      validator2,
      validator3,
    ])
    // delegate more to validator 4
    await parlia.delegate(validator4, {from: staker3, value: '4000000000000000000'}); // 4.0
    // check new active set
    assert.deepEqual(Array.from(await parlia.getValidators()), [
      validator4,
      validator1,
      validator2,
    ])
  });
  it("stake to non-existing validator", async () => {
    const {parlia} = await newMockContract(owner)
    await parlia.addValidator(validator1);
    await parlia.addValidator(validator3);
    await expectError(parlia.delegate(validator2, {
      from: staker1,
      value: '3000000000000000000'
    }), 'Staking: validator not found')
  });
  it("validator can claim both staking and commission rewards", async () => {
    const {parlia} = await newMockContract(owner, {epochBlockInterval: '50',})
    // create validator with 30% fee and 1 ether self stake
    await parlia.registerValidator(validator1, '3000', {from: validator1, value: '1000000000000000000'});
    await parlia.activateValidator(validator1);
    await waitForNextEpoch(parlia);
    // deposit 2 ether fee in different epochs
    await parlia.deposit(validator1, {from: validator1, value: '1000000000000000000'});
    await waitForNextEpoch(parlia);
    await parlia.deposit(validator1, {from: validator1, value: '1000000000000000000'});
    await waitForNextEpoch(parlia);
    // check rewards
    let validatorStakingFee = await parlia.getDelegatorFee(validator1, validator1)
    assert.equal(validatorStakingFee.toString(10), '1400000000000000000');
    let validatorFee = await parlia.getValidatorFee(validator1)
    assert.equal(validatorFee.toString(10), '600000000000000000');
    // claim
    await claimDelegatorFeeAndCheck(parlia, validator1, validator1, '1400000000000000000')
    await claimValidatorFeeAndCheck(parlia, validator1, '600000000000000000');
  })
  it("staker rewards with multiple delegations", async () => {
    const {parlia} = await newMockContract(owner, {epochBlockInterval: '50',})
    // create validator with 10% fee and 2 ether self stake
    await parlia.registerValidator(validator1, '1000', {from: validator1, value: '2000000000000000000'});
    await parlia.activateValidator(validator1);
    await waitForNextEpoch(parlia);
    // do first delegation
    await parlia.delegate(validator1, {from: staker1, value: '1000000000000000000'});
    await waitForNextEpoch(parlia);
    await parlia.delegate(validator1, {from: staker1, value: '1000000000000000000'});
    await waitForNextEpoch(parlia);
    // deposit some money
    await parlia.deposit(validator1, {from: validator1, value: '500000000000000000'});
    await waitForNextEpoch(parlia);
    await parlia.deposit(validator1, {from: validator1, value: '500000000000000000'});
    await waitForNextEpoch(parlia);
    // so, 2 eth is validator's share, 1 eth is staker share, plus validator gets 10% of fees then
    // + validator commission is 1 eth * 10% = 0.1 eth
    // + validator rewards is (1 eth * 90%) / 2 = 0.45 eth
    // + staker rewards i (1 eth * 90%) / 2 = 0.45 eth
    // total is 0.45+0.45+0.1 = 1 eth
    await claimValidatorFeeAndCheck(parlia, validator1, '100000000000000000');
    await claimDelegatorFeeAndCheck(parlia, validator1, validator1, '450000000000000000')
    await claimDelegatorFeeAndCheck(parlia, validator1, staker1, '450000000000000000')
  })
  it("validator w/o delegators should get all rewards", async () => {
    const {parlia} = await newMockContract(owner, {epochBlockInterval: '50',})
    await parlia.addValidator(validator1);
    await parlia.changeValidatorCommissionRate(validator1, '1000', {from: validator1}); // 10%
    await waitForNextEpoch(parlia);
    await parlia.deposit(validator1, {from: validator1, value: '1000000000000000000'}); // 1 ether
    await waitForNextEpoch(parlia);
    // check rewards
    await claimValidatorFeeAndCheck(parlia, validator1, '1000000000000000000')
  });
  it("only committed epoch is claimable", async () => {
    const {parlia} = await newMockContract(owner, {epochBlockInterval: '50',})
    // create validator with 10% fee and 2 ether self stake
    await parlia.registerValidator(validator1, '1000', {from: validator1, value: '2000000000000000000'});
    await parlia.activateValidator(validator1);
    await waitForNextEpoch(parlia);
    // deposit 1 ether and close one epoch, another deposit keep pending
    await parlia.deposit(validator1, {from: validator1, value: '1000000000000000000'}); // 1 ether
    await waitForNextEpoch(parlia);
    await parlia.deposit(validator1, {from: validator1, value: '1000000000000000000'}); // 1 ether
    // check rewards
    await claimValidatorFeeAndCheck(parlia, validator1, '100000000000000000')
    await claimDelegatorFeeAndCheck(parlia, validator1, validator1, '900000000000000000')
  })
  it("validator rewards are well-calculated", async () => {
    const {parlia} = await newMockContract(owner, {epochBlockInterval: '50',})
    await parlia.addValidator(validator1);
    await parlia.changeValidatorCommissionRate(validator1, '30', {from: validator1}); // 0.3%
    // delegate 1 ether to validator (100% of power)
    await parlia.delegate(validator1, {from: staker1, value: '1000000000000000000'}); // 1 ether
    // wait for the next epoch to apply fee scheme
    await waitForNextEpoch(parlia);
    // check constraints
    await expectError(parlia.deposit(validator1, {from: validator1, value: '0'}), 'Staking: deposit is zero');
    await expectError(parlia.deposit(validator4, {
      from: validator1,
      value: '1000000000000000000'
    }), 'Staking: validator not found');
    // validator get fees (1.1111 ether)
    await parlia.deposit(validator1, {from: validator1, value: '1000000000000000000'}); // 1 ether
    await parlia.deposit(validator1, {from: validator1, value: '100000000000000000'}); // 0.1 ether
    await parlia.deposit(validator1, {from: validator1, value: '10000000000000000'}); // 0.01 ether
    await parlia.deposit(validator1, {from: validator1, value: '1000000000000000'}); // 0.001 ether
    await parlia.deposit(validator1, {from: validator1, value: '100000000000000'}); // 0.0001 ether
    // wait before end of the epoch
    await waitForNextEpoch(parlia);
    // check rewards
    let validatorFee = await parlia.getValidatorFee(validator1)
    assert.equal(validatorFee.toString(10), '3333300000000000');
    let stakerFee = await parlia.getDelegatorFee(validator1, staker1)
    assert.equal(stakerFee.toString(10), '1107766700000000000');
    // let's skip next epoch w/ no rewards
    await waitForNextEpoch(parlia);
    // amounts should be the same
    validatorFee = await parlia.getValidatorFee(validator1)
    assert.equal(validatorFee.toString(10), '3333300000000000');
    stakerFee = await parlia.getDelegatorFee(validator1, staker1)
    assert.equal(stakerFee.toString(10), '1107766700000000000');
    // let's claim staker fee
    let delegatorBalanceBefore = new BigNumber(await web3.eth.getBalance(staker1));
    let {logs, txCost} = extractTxCost(await parlia.claimDelegatorFee(validator1, {from: staker1}));
    assert.equal(logs[0].event, 'Claimed')
    assert.equal(logs[0].args.amount, '1107766700000000000')
    let delegatorBalanceAfter = new BigNumber(await web3.eth.getBalance(staker1));
    assert.equal(delegatorBalanceAfter.minus(delegatorBalanceBefore).plus(txCost).toString(10), '1107766700000000000')
    // fee should be zero now for delegator
    validatorFee = await parlia.getValidatorFee(validator1)
    assert.equal(validatorFee.toString(10), '3333300000000000');
    stakerFee = await parlia.getDelegatorFee(validator1, staker1)
    assert.equal(stakerFee.toString(10), '0');
    // let's claim validator fee
    let validatorOwnerBalanceBefore = new BigNumber(await web3.eth.getBalance(validator1));
    ({txCost} = extractTxCost(await parlia.claimValidatorFee(validator1, {from: validator1})));
    let validatorOwnerBalanceAfter = new BigNumber(await web3.eth.getBalance(validator1));
    assert.equal(validatorOwnerBalanceAfter.minus(validatorOwnerBalanceBefore).plus(txCost).toString(10), validatorFee.toString(10));
  })
  it("no validator rewards for inactivity", async () => {
    const {parlia} = await newMockContract(owner, {
      epochBlockInterval: '50',
      misdemeanorThreshold: '5',
      felonyThreshold: '10'
    })
    await parlia.addValidator(validator1);
    await parlia.addValidator(validator2);
    assert.equal((await parlia.getValidatorStatus(validator1)).status.toString(), '1');
    assert.equal((await parlia.getValidatorStatus(validator2)).status.toString(), '1');
    // slash 5 times
    for (let i = 0; i < 5; i++) {
      await parlia.slash(validator2, {from: validator1});
    }
    assert.equal((await parlia.getValidatorStatus(validator1)).status.toString(), '1');
    assert.equal((await parlia.getValidatorStatus(validator2)).status.toString(), '1');
    // wait for the next epoch
    await waitForNextEpoch(parlia);
    // make sure fee is zero
    const validatorFee = await parlia.getValidatorFee(validator1)
    assert.equal(validatorFee.toString(), '0')
  });
  it("incorrect staking amounts", async () => {
    const {parlia} = await newMockContract(owner, {
      minValidatorStakeAmount: '0',
      minStakingAmount: '0',
    })
    await parlia.addValidator(validator1);
    await parlia.delegate(validator1, {
      from: staker1,
      value: '10000000000'
    }) // 0.00000001
    await expectError(parlia.delegate(validator1, {
      from: staker1,
      value: '1000000000'
    }), 'Staking: amount have a remainder') // 0.000000001
    await expectError(parlia.delegate(validator1, {
      from: staker1,
      value: '0'
    }), 'Staking: amount is too low') // 0
    await expectError(parlia.delegate(validator1, {
      from: staker1,
      value: '1000000001000000000'
    }), 'Staking: amount have a remainder') // 1.000000001
  });
  it("put validator in jail after N misses", async () => {
    const {parlia} = await newMockContract(owner, {
      epochBlockInterval: '300',
      misdemeanorThreshold: '10',
      felonyThreshold: '20'
    })
    await parlia.addValidator(validator1);
    await parlia.addValidator(validator2);
    assert.equal((await parlia.getValidatorStatus(validator1)).status.toString(), '1');
    assert.equal((await parlia.getValidatorStatus(validator2)).status.toString(), '1');
    // slash for 19 times
    for (let i = 0; i < 19; i++) {
      await parlia.slash(validator2, {from: validator1});
    }
    assert.equal((await parlia.getValidatorStatus(validator1)).status.toString(), '1');
    assert.equal((await parlia.getValidatorStatus(validator2)).status.toString(), '1');
    // slash one more time (20 total >= than felony threshold)
    await parlia.slash(validator2, {from: validator1});
    // status should change
    assert.equal((await parlia.getValidatorStatus(validator1)).status.toString(), '1');
    assert.equal((await parlia.getValidatorStatus(validator2)).status.toString(), '3');
  })
  it("validator can be released from jail by owner", async () => {
    const {parlia} = await newMockContract(owner, {
      epochBlockInterval: '50', // 50 blocks
      misdemeanorThreshold: '10', // penalty after 10 misses
      felonyThreshold: '5', // jail after 5 misses
      validatorJailEpochLength: '2', // put in jail for 2 epochs (100 blocks)
    })
    await parlia.addValidator(validator1);
    await parlia.addValidator(validator2);
    // we can't release validator if its active
    await expectError(parlia.releaseValidatorFromJail(validator2, {from: validator1}), 'Staking: validator not in jail')
    // all validators are active
    assert.equal((await parlia.getValidatorStatus(validator1)).status.toString(), '1');
    assert.equal((await parlia.getValidatorStatus(validator2)).status.toString(), '1');
    // let's wait for the next epoch (to be sure that slashing happen in one epoch)
    await waitForNextEpoch(parlia)
    // slash for 5 times
    for (let i = 0; i < 5; i++) {
      await parlia.slash(validator2, {from: validator1});
    }
    // now validator 2 is in jail
    let status2 = await parlia.getValidatorStatus(validator2)
    assert.equal(status2.slashesCount.toString(), '5');
    assert.equal(status2.status.toString(), '3');
    // try to release validator before jail period end
    await expectError(parlia.releaseValidatorFromJail(validator2, {from: validator2}), 'Staking: still in jail')
    // sleep until epoch 3 is reached
    await waitForNextEpoch(parlia);
    await waitForNextEpoch(parlia);
    // now release should work
    await expectError(parlia.releaseValidatorFromJail(validator2, {from: validator1}), 'Staking: only validator owner')
    await parlia.releaseValidatorFromJail(validator2, {from: validator2})
    // all validators are active
    assert.equal((await parlia.getValidatorStatus(validator1)).status.toString(), '1');
    assert.equal((await parlia.getValidatorStatus(validator2)).status.toString(), '1');
  })
  it("validator can undelegate initial stake", async () => {
    const {parlia} = await newMockContract(owner, {
      epochBlockInterval: '50', // 50 blocks
      undelegatePeriod: '0', // let claim in the next epoch
    })
    await parlia.registerValidator(validator1, '1000', {from: validator1, value: '10000000000000000000'}); // 10
    await waitForNextEpoch(parlia);
    let validatorStatus = await parlia.getValidatorStatus(validator1);
    assert.equal(validatorStatus.totalDelegated, '10000000000000000000');
    let initialStake = await parlia.getValidatorDelegation(validator1, validator1);
    assert.equal(initialStake.delegatedAmount, '10000000000000000000');
    await parlia.undelegate(validator1, '10000000000000000000', {from: validator1});
    await waitForNextEpoch(parlia);
    await claimDelegatorFeeAndCheck(parlia, validator1, validator1, '10000000000000000000');
    validatorStatus = await parlia.getValidatorStatus(validator1);
    assert.equal(validatorStatus.totalDelegated, '0');
    initialStake = await parlia.getValidatorDelegation(validator1, validator1);
    assert.equal(initialStake.delegatedAmount, '0');
  })
  it("validator owner is changed by existing owner", async () => {
    const {parlia} = await newMockContract(owner);
    await parlia.addValidator(validator1);
    assert.equal(await parlia.getValidatorByOwner(validator1), validator1);
    await expectError(parlia.changeValidatorOwner(validator1, owner, {from: validator2}), 'Staking: only validator owner');
    await parlia.changeValidatorOwner(validator1, owner, {from: validator1});
    assert.equal(await parlia.getValidatorByOwner(owner), validator1);
  })
  it("only validator owner can change commission rate", async () => {
    const {parlia} = await newMockContract(owner);
    await parlia.addValidator(validator1);
    await expectError(parlia.changeValidatorCommissionRate(validator1, '0', {from: validator2}), 'Staking: only validator owner');
  });
  it("delegator can claim new rewards w/o new delegations", async () => {
    const {parlia} = await newMockContract(owner, {epochBlockInterval: '5'});
    await parlia.addValidator(validator1);
    // delegate 1 ether (100%)
    await parlia.delegate(validator1, {from: staker1, value: '1000000000000000000'});
    await waitForNextEpoch(parlia);
    // deposit and claim it 1 ether
    await parlia.deposit(validator1, {from: validator1, value: '1000000000000000000'});
    await waitForNextEpoch(parlia);
    await claimDelegatorFeeAndCheck(parlia, validator1, staker1, '1000000000000000000');
    await waitForNextEpoch(parlia);
    // deposit 1 more ether and claim it
    await parlia.deposit(validator1, {from: validator1, value: '1000000000000000000'});
    await waitForNextEpoch(parlia);
    // await debug(parlia.claimDelegatorFee(validator1, {from: staker1}))
    await claimDelegatorFeeAndCheck(parlia, validator1, staker1, '1000000000000000000', true);
  })
  it("benchmark delegator reward claim", async () => {
    const {parlia} = await newMockContract(owner, {
      epochBlockInterval: '1',
    });
    await parlia.addValidator(validator1);
    await parlia.delegate(validator1, {from: staker1, value: '1000000000000000000'}); // 1.0 (100% share)
    const costOfClaims = [1, 10]
    for (const blocks of costOfClaims) {
      for (let i = 0; i < blocks; i++) {
        await parlia.deposit(validator1, {from: validator1, value: '1000000000000000000'}); // 1.0
      }
      const result = await parlia.claimDelegatorFee(validator1, {from: staker1})
      console.log(` + ${blocks} blocks, amount=${new BigNumber(result.logs[0].args.amount).dividedBy(1e18).toString(10)}, gas=${result.receipt.gasUsed}`);
    }
  })
  it("jailed validator is removed from active validator set after new epoch", async () => {
    const {parlia} = await newMockContract(owner, {
      genesisValidators: [ validator1, validator2 ],
      epochBlockInterval: '50',
      validatorJailEpochLength: '1',
      misdemeanorThreshold: '5',
      felonyThreshold: '10',
    });
    assert.deepEqual(Array.from(await parlia.getValidators()).sort(), [
      validator1,
      validator2,
    ])
    for (let i = 0; i < 10; i++) {
      await parlia.slash(validator1);
    }
    assert.deepEqual(Array.from(await parlia.getValidators()).sort(), [
      validator2,
    ])
    await waitForNextEpoch(parlia)
    await waitForNextEpoch(parlia)
    await parlia.releaseValidatorFromJail(validator1, {from: validator1});
    assert.deepEqual(Array.from(await parlia.getValidators()).sort(), [
      validator1,
      validator2,
    ])
  });
  it("user can redelegate his staking rewards", async () => {
    const {parlia} = await newMockContract(owner, {
      genesisValidators: [ validator1 ],
      epochBlockInterval: '10',
    });
    // delegate 1 ether and distribute 1 ether as rewards (100% APY) with some dust
    await parlia.delegate(validator1, {from: staker1, value: '1000000000000000000'});
    await waitForNextEpoch(parlia);
    await parlia.deposit(validator1, {value: '1000000000000000123'});
    await waitForNextEpoch(parlia);
    // now user should have 1 ether claimable as rewards
    let claimableRewards = await parlia.getDelegatorFee(validator1, staker1);
    assert.equal(claimableRewards.toString(), '1000000000000000123')
    let delegation = await parlia.getValidatorDelegation(validator1, staker1);
    assert.equal(delegation.delegatedAmount.toString(), '1000000000000000000')
    // now lets redelegate our rewards
    let redelegateAmount = await parlia.calcAvailableForRedelegateAmount(validator1, staker1);
    assert.equal(redelegateAmount.amountToStake.toString(), '1000000000000000000');
    assert.equal(redelegateAmount.rewardsDust.toString(), '123');
    const res1 = await parlia.redelegateDelegatorFee(validator1, {from: staker1});
    assert.equal(res1.logs[1].event, 'Redelegated');
    assert.equal(res1.logs[1].args.validator, validator1);
    assert.equal(res1.logs[1].args.staker, staker1);
    assert.equal(res1.logs[1].args.amount.toString(), '1000000000000000000');
    assert.equal(res1.logs[1].args.dust, '123');
    await waitForNextEpoch(parlia);
    // now user should have 1 ether claimable as rewards
    claimableRewards = await parlia.getDelegatorFee(validator1, staker1);
    assert.equal(claimableRewards.toString(), '0')
    delegation = await parlia.getValidatorDelegation(validator1, staker1);
    assert.equal(delegation.delegatedAmount.toString(), '2000000000000000000')
  });
});
