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
  plugins: [
    "solidity-coverage"
  ]
};
