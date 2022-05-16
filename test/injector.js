/** @var artifacts {Array} */
/** @var web3 {Web3} */
/** @function contract */
/** @function it */
/** @function before */
/** @var assert */

const {newMockContract} = require("./helper");

contract("Injector", async (accounts) => {
  const [owner] = accounts
  it("migration is working fine", async () => {
    const {staking, slashingIndicator, systemReward, governance, chainConfig} = await newMockContract(owner);
    for (const contract of [staking]) {
      assert.equal(staking.address, await contract.getStaking());
      assert.equal(slashingIndicator.address, await contract.getSlashingIndicator());
      assert.equal(systemReward.address, await contract.getSystemReward());
      assert.equal(governance.address, await contract.getGovernance());
      assert.equal(chainConfig.address, await contract.getChainConfig());
    }
  });
});
