/** @var artifacts {Array} */
/** @var web3 {Web3} */
/** @function contract */
/** @function it */
/** @function before */
/** @var assert */

const Parlia = artifacts.require("Parlia");

const {newGovernanceContract, addValidator, removeValidator, newMockContract} = require('./helper')
const BigNumber = require('bignumber.js');

contract("Parlia", async (accounts) => {
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
  it("system fee is well calculated", async () => {
    const {parlia} = await newMockContract(owner, {systemTreasury: treasury,})
    // send 1 ether
    await web3.eth.sendTransaction({from: owner, to: parlia.address, value: '1000000000000000000'}); // 1 ether
    // balance and state should be 1
    assert.equal((await web3.eth.getBalance(parlia.address)).toString(), '1000000000000000000')
    assert.equal((await parlia.getSystemFee()).toString(), '1000000000000000000')
    // send 1 ether
    await web3.eth.sendTransaction({from: owner, to: parlia.address, value: '1000000000000000000'}); // 1 ether
    // balance and state should be 2
    assert.equal((await web3.eth.getBalance(parlia.address)).toString(), '2000000000000000000')
    assert.equal((await parlia.getSystemFee()).toString(), '2000000000000000000')
    // claim to treasury
    await parlia.claimSystemFee({from: treasury});
    // balance and state should be 0
    assert.equal((await web3.eth.getBalance(parlia.address)).toString(), '0')
    assert.equal((await parlia.getSystemFee()).toString(), '0')
  })
  it("system fee is auto claimable after 50 ether", async () => {
    const {parlia} = await newMockContract(owner, {systemTreasury: treasury,})
    const initialBalance = new BigNumber((await web3.eth.getBalance(treasury)).toString());
    // send 49 ether
    await web3.eth.sendTransaction({from: owner, to: parlia.address, value: '49000000000000000000'}); // 49 ether
    // balance shouldn't change
    assert.equal((await web3.eth.getBalance(treasury)).toString(), initialBalance.toString(10))
    assert.equal((await parlia.getSystemFee()).toString(), '49000000000000000000')
    // send 2 ether more
    await web3.eth.sendTransaction({from: owner, to: parlia.address, value: '2000000000000000000'}); // 2 ether
    // fee is not claimable anymore
    assert.equal((await web3.eth.getBalance(treasury)).toString(), initialBalance.plus('51000000000000000000').toString(10))
    assert.equal((await parlia.getSystemFee()).toString(), '0')
  })
  it("test contract genesis creation", async () => {
    await Parlia.new(
      [
        '0x0000000000000000000000000000000000000001',
        '0x0000000000000000000000000000000000000002',
        '0x0000000000000000000000000000000000000003',
      ],
      '0x0000000000000000000000000000000000000000',
      '22',
      '300',
      '50',
      '150',
      '7',
      '0',
    );
  })
});
