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

const {addValidator, removeValidator} = require('./helper')

contract("Parlia", async (accounts) => {
  const [owner] = accounts
  const newGovernanceContract = async () => {
    const governance = await Governance.new(owner, 1),
      parlia = await Parlia.new([]);
    governance.initManually('0x0000000000000000000000000000000000000000', governance.address, parlia.address);
    parlia.initManually('0x0000000000000000000000000000000000000000', governance.address, parlia.address);
    return [parlia, governance]
  }
  const newMockContract = async () => {
    const governance = await Governance.new(owner, 1),
      parlia = await FakeStaking.new();
    governance.initManually('0x0000000000000000000000000000000000000000', governance.address, parlia.address);
    parlia.initManually('0x0000000000000000000000000000000000000000', governance.address, parlia.address);
    return [parlia, governance]
  }
  it("add remove validator", async () => {
    const [parlia, governance] = await newGovernanceContract()
    assert.equal(await parlia.isValidator('0x00A601f45688DbA8a070722073B015277cF36725'), false)
    const {receipt: {rawLogs: rawLogs1}} = await addValidator(governance, parlia, '0x00A601f45688DbA8a070722073B015277cF36725', owner),
      [, log1] = rawLogs1
    assert.equal(log1.topics[0], web3.utils.keccak256('ValidatorAdded(address)'))
    assert.equal(log1.data, `0x00000000000000000000000000a601f45688dba8a070722073b015277cf36725`)
    assert.equal(await parlia.isValidator('0x00A601f45688DbA8a070722073B015277cF36725'), true)
    const validators1 = await parlia.getValidators()
    assert.deepEqual(validators1, ['0x00A601f45688DbA8a070722073B015277cF36725'])
    const {receipt: {rawLogs: rawLogs2}} = await removeValidator(governance, parlia, '0x00A601f45688DbA8a070722073B015277cF36725', owner),
      [, log2] = rawLogs2
    assert.equal(log2.topics[0], web3.utils.keccak256('ValidatorRemoved(address)'))
    assert.equal(log2.data, `0x00000000000000000000000000a601f45688dba8a070722073b015277cf36725`)
    assert.equal(await parlia.isValidator('0x00A601f45688DbA8a070722073B015277cF36725'), false)
    const validators2 = await parlia.getValidators()
    assert.deepEqual(validators2, [])
  });
  it("remove first added validator", async () => {
    const [parlia, governance] = await newGovernanceContract()
    await addValidator(governance, parlia, '0x0000000000000000000000000000000000000001', owner)
    await addValidator(governance, parlia, '0x0000000000000000000000000000000000000002', owner)
    await addValidator(governance, parlia, '0x0000000000000000000000000000000000000003', owner)
    assert.deepEqual(Array.from(await parlia.getValidators()).sort(), [
      '0x0000000000000000000000000000000000000001',
      '0x0000000000000000000000000000000000000002',
      '0x0000000000000000000000000000000000000003',
    ])
    await removeValidator(governance, parlia, '0x0000000000000000000000000000000000000001', owner)
    assert.deepEqual(Array.from(await parlia.getValidators()).sort(), [
      '0x0000000000000000000000000000000000000002',
      '0x0000000000000000000000000000000000000003',
    ])
  })
  it("remove some validator from the list", async () => {
    const governance = await Governance.new(owner, 1),
      parlia = await Parlia.new([]);
    governance.initManually('0x0000000000000000000000000000000000000000', governance.address, parlia.address);
    parlia.initManually('0x0000000000000000000000000000000000000000', governance.address, parlia.address);
    await addValidator(governance, parlia, '0x0000000000000000000000000000000000000001', owner)
    await addValidator(governance, parlia, '0x0000000000000000000000000000000000000002', owner)
    await addValidator(governance, parlia, '0x0000000000000000000000000000000000000003', owner)
    assert.deepEqual(Array.from(await parlia.getValidators()).sort(), [
      '0x0000000000000000000000000000000000000001',
      '0x0000000000000000000000000000000000000002',
      '0x0000000000000000000000000000000000000003',
    ])
    await removeValidator(governance, parlia, '0x0000000000000000000000000000000000000002', owner)
    assert.deepEqual(Array.from(await parlia.getValidators()).sort(), [
      '0x0000000000000000000000000000000000000001',
      '0x0000000000000000000000000000000000000003',
    ])
  })
  it("remove last validator from the list", async () => {
    const [parlia, governance] = await newGovernanceContract()
    await addValidator(governance, parlia, '0x0000000000000000000000000000000000000001', owner)
    await addValidator(governance, parlia, '0x0000000000000000000000000000000000000002', owner)
    await addValidator(governance, parlia, '0x0000000000000000000000000000000000000003', owner)
    assert.deepEqual(Array.from(await parlia.getValidators()).sort(), [
      '0x0000000000000000000000000000000000000001',
      '0x0000000000000000000000000000000000000002',
      '0x0000000000000000000000000000000000000003',
    ])
    await removeValidator(governance, parlia, '0x0000000000000000000000000000000000000003', owner)
    assert.deepEqual(Array.from(await parlia.getValidators()).sort(), [
      '0x0000000000000000000000000000000000000001',
      '0x0000000000000000000000000000000000000002',
    ])
  })
  it("system fee is well calculated", async () => {
    const [parlia, governance] = await newMockContract()
    await web3.eth.sendTransaction({from: owner, to: parlia.address, value: '1000000000000000000'}); // 1 ether
    let systemFee = await parlia.getSystemFee()
    assert.equal(systemFee.toString(), '1000000000000000000')
    await web3.eth.sendTransaction({from: owner, to: parlia.address, value: '1000000000000000000'}); // 1 ether
    systemFee = await parlia.getSystemFee()
    assert.equal(systemFee.toString(), '2000000000000000000')

  })
});
