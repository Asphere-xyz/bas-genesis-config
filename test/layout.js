/** @var artifacts {Array} */
/** @var web3 {Web3} */
/** @function contract */
/** @function it */
/** @function before */
/** @var assert */

const StorageLayoutChecker = artifacts.require("StorageLayoutChecker");

contract("StorageLayoutChecker", async () => {
  it("inherited from injector contracts always start with 101 slot", async () => {
    const storageLayoutChecker = await StorageLayoutChecker.new(
      '0x0000000000000000000000000000000000000000',
      '0x0000000000000000000000000000000000000000',
      '0x0000000000000000000000000000000000000000',
      '0x0000000000000000000000000000000000000000',
      '0x0000000000000000000000000000000000000000',
      '0x0000000000000000000000000000000000000000',
      '0x0000000000000000000000000000000000000000',
      '0x0000000000000000000000000000000000000000',
    );
    await storageLayoutChecker.makeSureInjectorLayoutIsNotCorrupted();
  });
});
