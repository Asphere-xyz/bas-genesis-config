/** @var artifacts {Array} */
/** @var web3 {Web3} */
/** @function contract */
/** @function it */
/** @function before */
/** @var assert */

const {newMockContract, waitForNextEpoch} = require("./helper");

contract("Governance", async (accounts) => {
  const [owner, validator1] = accounts
  it("simple proposal should work", async () => {
    const {parlia, governance, deployer} = await newMockContract(owner);
    await parlia.addValidator(validator1);
    await parlia.delegate(validator1, {from: validator1, value: '1000000000000000000'});
    await waitForNextEpoch(parlia);
    const r1 = await governance.propose(
      [deployer.address],
      ['0x00'],
      [deployer.contract.methods.addDeployer(owner).encodeABI()],
      'Whitelist new deployer')
    const {proposalId} = r1.logs[0].args
    assert.equal(r1.logs[0].event, 'ProposalCreated')
    const descriptionHash = web3.utils.keccak256('Whitelist new deployer')
    const r2 = await governance.castVote(proposalId, 1, {from: validator1})
    assert.equal(r2.logs[0].event, 'VoteCast')
    const r3 = await governance.execute(
      [deployer.address],
      ['0x00'],
      [deployer.contract.methods.addDeployer(owner).encodeABI()],
      descriptionHash,
    );
    assert.equal(r3.logs[0].event, 'ProposalExecuted')
  })
});
