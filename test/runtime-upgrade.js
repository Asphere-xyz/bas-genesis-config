/** @var artifacts {Array} */
/** @var web3 {Web3} */
/** @function contract */
/** @function it */
/** @function before */
/** @var assert */

const {newMockContract, waitForNextEpoch, advanceBlocks} = require("./helper");
const AbiCoder = require("web3-eth-abi");

const FakeStakingWithMethod = artifacts.require('FakeStakingWithMethod');

contract("RuntimeUpgrade", async (accounts) => {
  const [owner, validator1, validator2] = accounts
  const injectorBytecode = (systemSmartContracts, {bytecode}) => {
    const injectorArgs = AbiCoder.encodeParameters(['address', 'address', 'address', 'address', 'address', 'address', 'address', 'address',], systemSmartContracts)
    return bytecode + injectorArgs.substr(2)
  }
  it("its possible to upgrade smart contract", async () => {
    const {runtimeUpgrade} = await newMockContract(owner, {});
    const systemSmartContracts = await runtimeUpgrade.getSystemContracts();
    const fakeStakingBytecode = injectorBytecode(systemSmartContracts, FakeStakingWithMethod);
    const res = await runtimeUpgrade.upgradeSystemSmartContract(systemSmartContracts[0], fakeStakingBytecode, '0x');
    assert.equal(res.logs[0].event, 'Upgraded')
    assert.equal(res.logs[0].args.account, systemSmartContracts[0])
    assert.equal(res.logs[0].args.bytecode, fakeStakingBytecode)
    const newFakeStaking = await FakeStakingWithMethod.at(systemSmartContracts[0]);
    const res2 = await newFakeStaking.thisIsMethod();
    assert.equal(res2, '123');
  });
  it("upgrade though governance should work", async () => {
    const {parlia, runtimeUpgrade, governance} = await newMockContract(owner, {
      genesisValidators: [validator1],
      votingPeriod: '5',
    });
    await parlia.delegate(validator1, {value: '1000000000000000000', from: owner});
    await waitForNextEpoch(parlia);
    const runtimeUpgradeContract = new web3.eth.Contract(runtimeUpgrade.abi);
    const systemSmartContracts = await runtimeUpgrade.getSystemContracts();
    const upgradeCall = await runtimeUpgradeContract.methods.upgradeSystemSmartContract(systemSmartContracts[0], injectorBytecode(systemSmartContracts, FakeStakingWithMethod), '0x').encodeABI()
    const desc = `Runtime upgrade for contract (${systemSmartContracts[0]})`;
    const res1 = await governance.propose([runtimeUpgrade.address], ['0'], [upgradeCall], desc, {from: validator1}),
      {proposalId} = res1.logs[0].args;
    // validator 1 votes for the proposal and proposal is still active
    await governance.castVote(proposalId, '1', {from: validator1});
    assert.equal(await governance.state(proposalId), '1')
    await advanceBlocks(5);
    await governance.execute([runtimeUpgrade.address], ['0'], [upgradeCall], web3.utils.keccak256(desc));
    const newFakeStaking = await FakeStakingWithMethod.at(systemSmartContracts[0]);
    const res2 = await newFakeStaking.thisIsMethod();
    assert.equal(res2, '123');
  })
});
