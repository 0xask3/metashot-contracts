const HDWalletProvider = require("@truffle/hdwallet-provider");
require("dotenv").config();
module.exports = {
  networks: {
    development: {
      host: "127.0.0.1", // Localhost (default: none)
      port: 8545, // Standard Ethereum port (default: none)
      network_id: "*", // Any network (default: none)
    },
    ropsten: {
      provider: () =>
        new HDWalletProvider(process.env.MNEMONIC, process.env.ROPSTEN, 0),
      network_id: 3,
      timeoutBlocks: 5000000, // # of blocks before a deployment times out  (minimum/default: 50)
      skipDryRun: true, // Skip dry run before migrations? (default: false for public nets )
      skipDryRun: true     // Skip dry run before migrations? (default: false for public nets )
    },
    kovan: {
      provider: () =>
        new HDWalletProvider(process.env.MNEMONIC, process.env.KOVAN),
      network_id: 42,
      skipDryRun: true,
    },
    rinkeby: {
      provider: () =>
        new HDWalletProvider(process.env.MNEMONIC, process.env.RINKEBY),
      network_id: 4,
      skipDryRun: true, // Skip dry run before migrations? (default: false for public nets )
    },
    goerli: {
      provider: () =>
        new HDWalletProvider(process.env.MNEMONIC, process.env.GOERLI),
      network_id: 5, // eslint-disable-line camelcase
    },
    bsctestnet: {
      provider: () =>
        new HDWalletProvider(process.env.MNEMONIC, process.env.BSCTESTNET),
      network_id: 97,
      skipDryRun: true,
    },
    polygon: {
      provider: () =>
        new HDWalletProvider(process.env.MNEMONIC, process.env.POLYGON),
      network_id: 137,
      skipDryRun: true,
    },
    mumbai: {
      provider: () =>
        new HDWalletProvider(process.env.MNEMONIC, process.env.MUMBAI),
      network_id: 80001,
      skipDryRun: true,
    },
    bscmainnet: {
      provider: () =>
        new HDWalletProvider(process.env.MNEMONIC, process.env.BSCMAINNET),
      network_id: 56,
      skipDryRun: true,
    },
    avaxtestnet: {
      provider: () =>
        new HDWalletProvider(process.env.MNEMONIC, process.env.AVAXTESTNET),
      network_id: 43113,
      skipDryRun: true,
    },
    avaxmainnet: {
      provider: () =>
        new HDWalletProvider(process.env.MNEMONIC, process.env.AVAXMAINNET),
      network_id: 43114,
      skipDryRun: true,
    },
    mainnet: {
      provider: () =>
        new HDWalletProvider(process.env.MNEMONIC, process.env.MAINNET, 0),
      network_id: 1,
      gasPrice: 50000000000,
      timeoutBlocks: 5000000, // # of blocks before a deployment times out  (minimum/default: 50)
      skipDryRun: true, // Skip dry run before migrations? (default: false for public nets )
      from: process.env.ACCOUNT,
    },
  },
  //
  // Configure your compilers
  compilers: {
    solc: {
      version: "0.8.15", // Fetch exact version from solc-bin (default: truffle's version)
      // docker: true,        // Use "0.5.1" you've installed locally with docker (default: false)
      settings: {
        // See the solidity docs for advice about optimization and evmVersion
        optimizer: {
          enabled: true,
          runs: 9999,
        },
        //  evmVersion: "byzantium"
      },
    },
  },

  plugins: ["truffle-plugin-verify"],
  api_keys: {
    etherscan: process.env.ETHERAPI, // Add  API key
    bscscan: process.env.BSCSCAN,
    snowtrace: process.env.SNOWTRACE,
    polygonscan: process.env.POLYGONSCAN
  },
};
