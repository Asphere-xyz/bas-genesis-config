/** @var artifacts {Array} */
/** @var web3 {Web3} */
/** @function contract */
/** @function it */
/** @function before */
/** @var assert */

const {newMockContract} = require('./helper')

contract("Parlia", async (accounts) => {
  const [owner] = accounts
  it("can add or remove validator", async () => {
    const {parlia} = await newMockContract(owner);
    assert.equal(await parlia.isValidator('0x00A601f45688DbA8a070722073B015277cF36725'), false)
    const res1 = await parlia.addValidator('0x00A601f45688DbA8a070722073B015277cF36725')
    assert.equal(res1.logs[0].event, 'ValidatorAdded')
    assert.equal(res1.logs[0].args.validator, '0x00A601f45688DbA8a070722073B015277cF36725')
    assert.equal(await parlia.isValidator('0x00A601f45688DbA8a070722073B015277cF36725'), true)
    const validators1 = await parlia.getValidators()
    assert.deepEqual(validators1, ['0x00A601f45688DbA8a070722073B015277cF36725'])
    const res2 = await parlia.removeValidator('0x00A601f45688DbA8a070722073B015277cF36725')
    assert.equal(res2.logs[0].event, 'ValidatorRemoved')
    assert.equal(res2.logs[0].args.validator, '0x00A601f45688DbA8a070722073B015277cF36725')
    assert.equal(await parlia.isValidator('0x00A601f45688DbA8a070722073B015277cF36725'), false)
    const validators2 = await parlia.getValidators()
    assert.deepEqual(validators2, [])
  });
  it("remove firstly added validator", async () => {
    const {parlia} = await newMockContract(owner)
    await parlia.addValidator('0x0000000000000000000000000000000000000001')
    await parlia.addValidator('0x0000000000000000000000000000000000000002')
    await parlia.addValidator('0x0000000000000000000000000000000000000003')
    assert.deepEqual(Array.from(await parlia.getValidators()).sort(), [
      '0x0000000000000000000000000000000000000001',
      '0x0000000000000000000000000000000000000002',
      '0x0000000000000000000000000000000000000003',
    ])
    await parlia.removeValidator('0x0000000000000000000000000000000000000001')
    assert.deepEqual(Array.from(await parlia.getValidators()).sort(), [
      '0x0000000000000000000000000000000000000002',
      '0x0000000000000000000000000000000000000003',
    ])
  })
  it("remove validator from the center of the list", async () => {
    const {parlia} = await newMockContract(owner)
    await parlia.addValidator('0x0000000000000000000000000000000000000001')
    await parlia.addValidator('0x0000000000000000000000000000000000000002')
    await parlia.addValidator('0x0000000000000000000000000000000000000003')
    assert.deepEqual(Array.from(await parlia.getValidators()).sort(), [
      '0x0000000000000000000000000000000000000001',
      '0x0000000000000000000000000000000000000002',
      '0x0000000000000000000000000000000000000003',
    ])
    await parlia.removeValidator('0x0000000000000000000000000000000000000002')
    assert.deepEqual(Array.from(await parlia.getValidators()).sort(), [
      '0x0000000000000000000000000000000000000001',
      '0x0000000000000000000000000000000000000003',
    ])
  })
  it("remove last validator from the list", async () => {
    const {parlia} = await newMockContract(owner)
    await parlia.addValidator('0x0000000000000000000000000000000000000001')
    await parlia.addValidator('0x0000000000000000000000000000000000000002')
    await parlia.addValidator('0x0000000000000000000000000000000000000003')
    assert.deepEqual(Array.from(await parlia.getValidators()).sort(), [
      '0x0000000000000000000000000000000000000001',
      '0x0000000000000000000000000000000000000002',
      '0x0000000000000000000000000000000000000003',
    ])
    await parlia.removeValidator('0x0000000000000000000000000000000000000003')
    assert.deepEqual(Array.from(await parlia.getValidators()).sort(), [
      '0x0000000000000000000000000000000000000001',
      '0x0000000000000000000000000000000000000002',
    ])
  })
});
