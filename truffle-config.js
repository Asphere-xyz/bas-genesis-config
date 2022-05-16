const ENABLE_GAS_REPORTER = false;

let mochaOptions = {enableTimeouts: false,}
if (ENABLE_GAS_REPORTER) {
  Object.assign(mochaOptions, {
    reporterOptions: {
      showTimeSpent: true,
      showMethodSig: true,
    },
    reporter: 'eth-gas-reporter'
  })
}

module.exports = {
  compilers: {
    solc: {
      version: "0.8.11",
      settings: {
        optimizer: {
          enabled: true,
          runs: 100
        },
      }
    }
  },
  networks: {
    ganache: {
      host: "localhost",
      port: 7545,
      network_id: "*", // Match any network id
      gas: 100_000_000
    },
  },
  mocha: mochaOptions,
  plugins: [
    "solidity-coverage"
  ]
};
