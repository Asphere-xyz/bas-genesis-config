const ENABLE_GAS_REPORTER = false;

let mochaOptions = {enableTimeouts: false}
if (ENABLE_GAS_REPORTER) {
  Object.assign(mochaOptions, {
    reporterOptions: {
      showTimeSpent: true,
      showMethodSig: true
    },
    reporter: 'eth-gas-reporter'
  })
}

module.exports = {
  compilers: {
    solc: {
      version: "0.8.14",
      settings: {
        optimizer: {
          enabled: true,
          runs: 100
        }
      }
    }
  },
  networks: {
    develop: {
      host: "localhost",
      port: 8545,
      network_id: "*"
    },
    ganache: {
      host: "localhost",
      port: 7545,
      network_id: "*",
      gas: 100_000_000
    }
  },
  mocha: mochaOptions,
  plugins: [
    "solidity-coverage"
  ]
};
