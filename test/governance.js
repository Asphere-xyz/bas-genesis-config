/** @var artifacts {Array} */
/** @var web3 {Web3} */
/** @function contract */
/** @function it */
/** @function before */
/** @var assert */

const {newMockContract, waitForNextEpoch} = require('./helper')

contract("Governance", async (accounts) => {
  const [owner, validator1, validator2, owner1, owner2] = accounts;
  it("voting power is well distributed for validators with different owners", async () => {
    const {parlia, governance} = await newMockContract(owner, {
      genesisValidators: [validator1, validator2],
    });
    await parlia.delegate(validator1, {value: '1000000000000000000', from: owner});
    await parlia.delegate(validator2, {value: '1000000000000000000', from: owner});
    await waitForNextEpoch(parlia);
    // let's check voting supply and voting powers for validators
    let votingSupply = await governance.getVotingSupply();
    assert.equal(votingSupply.toString(), '2000000000000000000');
    assert.equal((await governance.getVotingPower(validator1)).toString(), '1000000000000000000');
    assert.equal((await governance.getVotingPower(validator2)).toString(), '1000000000000000000');
    // now lets change validator owner
    await parlia.changeValidatorOwner(validator1, owner1, {from: validator1});
    await parlia.changeValidatorOwner(validator2, owner2, {from: validator2});
    // let's re-check voting supply and voting powers for validators, it should be the same
    votingSupply = await governance.getVotingSupply();
    assert.equal(votingSupply.toString(), '2000000000000000000');
    assert.equal((await governance.getVotingPower(owner1)).toString(), '1000000000000000000');
    assert.equal((await governance.getVotingPower(owner2)).toString(), '1000000000000000000');
  });
});
