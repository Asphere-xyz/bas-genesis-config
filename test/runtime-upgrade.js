/** @var artifacts {Array} */
/** @var web3 {Web3} */
/** @function contract */
/** @function it */
/** @function before */
/** @var assert */

const FakeRuntimeUpgradeEvmHook = artifacts.require('FakeRuntimeUpgradeEvmHook');
const {newMockContract} = require("./helper");

contract("RuntimeUpgrade", async (accounts) => {
  const [owner] = accounts
  it("migration is working fine", async () => {
    const evmHook = await FakeRuntimeUpgradeEvmHook.new();
    const {runtimeUpgrade} = await newMockContract(owner, {runtimeUpgradeEvmHook: evmHook.address});
    assert.equal(await runtimeUpgrade.getEvmHookAddress(), evmHook.address);
    const systemSmartContracts = await runtimeUpgrade.getSystemContracts();
    const res = await runtimeUpgrade.upgradeSystemSmartContract(systemSmartContracts[0], '0xbadcab1e', '0x');
    assert.equal(res.logs[0].event, 'SmartContractUpgrade')
    assert.equal(res.logs[0].args.contractAddress, systemSmartContracts[0])
    assert.equal(res.logs[0].args.newByteCode, '0xbadcab1e')
  });
});
