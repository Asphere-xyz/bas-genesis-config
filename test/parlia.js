/** @var artifacts {Array} */
/** @var web3 {Web3} */
/** @function contract */
/** @function it */
/** @function before */
/** @var assert */

const {newGovernanceContract, addValidator, removeValidator} = require('./helper')

contract("Staking", async (accounts) => {
  const [owner, treasury] = accounts
  it("governance can add or remove validator", async () => {
    const {governance, parlia} = await newGovernanceContract(owner);
    assert.equal(await parlia.isValidator('0x00A601f45688DbA8a070722073B015277cF36725'), false)
    const {receipt: {rawLogs: rawLogs1}} = await addValidator(governance, parlia, '0x00A601f45688DbA8a070722073B015277cF36725', owner),
      [, log1] = rawLogs1
    assert.equal(log1.topics[0], web3.utils.keccak256('ValidatorAdded(address,address,uint8,uint16)'))
    assert.equal(log1.data, `0x00000000000000000000000000a601f45688dba8a070722073b015277cf3672500000000000000000000000000a601f45688dba8a070722073b015277cf3672500000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000`)
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
  it("remove firstly added validator", async () => {
    const {parlia, governance} = await newGovernanceContract(owner)
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
  it("remove validator from the center of the list", async () => {
    const {parlia, governance} = await newGovernanceContract(owner)
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
    const {parlia, governance} = await newGovernanceContract(owner)
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
  it("test contract genesis creation", async () => {
    const Staking = artifacts.require("Staking");
    await Staking.new(
      [
        '0x0000000000000000000000000000000000000001',
        '0x0000000000000000000000000000000000000002',
        '0x0000000000000000000000000000000000000003',
      ],
      '22',
      '300',
      '50',
      '150',
      '7',
      '0',
    );
  })
});
