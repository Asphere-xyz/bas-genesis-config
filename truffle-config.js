module.exports = {
  compilers: {
    solc: {
      version: "0.8.11",
      settings: {
        optimizer: {
          enabled: true,
          runs: 200
        },
      }
    }
  },
  mocha: {
    enableTimeouts: false,
    // reporterOptions: {
    //   showTimeSpent: true,
    //   showMethodSig: true,
    // },
    // reporter: 'eth-gas-reporter'
  },
  plugins: [
    "solidity-coverage"
  ]
};
