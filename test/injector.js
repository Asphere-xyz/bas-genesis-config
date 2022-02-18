/** @var artifacts {Array} */
/** @var web3 {Web3} */
/** @function contract */
/** @function it */
/** @function before */
/** @var assert */

const {newMockContract} = require("./helper");

const Deployer = artifacts.require("ContractDeployer");
const Governance = artifacts.require("Governance");
const Staking = artifacts.require("Staking");

contract("Injector", async (accounts) => {
  const [owner] = accounts
  it("migration is working fine", async () => {
    const {staking, slashingIndicator, systemReward, contractDeployer, governance} = await newMockContract(owner);
    for (const contract of [staking]) {
      assert.equal(staking.address, await contract.getStaking());
      assert.equal(slashingIndicator.address, await contract.getSlashingIndicator());
      assert.equal(systemReward.address, await contract.getSystemReward());
      assert.equal(contractDeployer.address, await contract.getContractDeployer());
      assert.equal(governance.address, await contract.getGovernance());
    }
  });
  it("consensus init is working", async () => {
    const testInjector = async (classType, ...args) => {
      const deployer = await classType.new(...args);
      await deployer.init()
      assert.equal(await deployer.getStaking(), '0x0000000000000000000000000000000000001000')
      assert.equal(await deployer.getSlashingIndicator(), '0x0000000000000000000000000000000000001001')
      assert.equal(await deployer.getSystemReward(), '0x0000000000000000000000000000000000001002')
      assert.equal(await deployer.getContractDeployer(), '0x0000000000000000000000000000000000007001')
      assert.equal(await deployer.getGovernance(), '0x0000000000000000000000000000000000007002')
    }
    await testInjector(Deployer, [])
    await testInjector(Governance, owner, '1')
    await testInjector(Staking, [], '0x0000000000000000000000000000000000000000', '0', '0', '0', '0', '0', '0')
  })
});
