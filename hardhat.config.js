require("dotenv").config({ path: "../../.env" });
require("@nomiclabs/hardhat-waffle");
require("solidity-coverage");

const defaultNetwork = "private";

const KALEIDO_URL = process.env.MAPLE_KALEIDO_URL || "";
const KALEIDO_MNEMONIC = process.env.MAPLE_MNEMONIC || "";

const KOVAN_NODE_URL = process.env.KOVAN_NODE_URL || "";
const KOVAN_MNEMONIC = process.env.KOVAN_MNEMONIC || "";

const MAINNET_NODE_URL = process.env.MAINNET_NODE_URL || "";
const MAINNET_MNEMONIC = process.env.MAINNET_MNEMONIC || "";

module.exports = {
  defaultNetwork,
  gasReporter: {
    showMethodSig: true,
    currency: "KRW",
  },

  networks: {
    localhost: {
      url: "http://localhost:8545",
    },
    private: {
      gasMultiplier: 5,
      timeout: 30000,
      gas: 9500000,
      gasPrice: 0,
      chainId: 367662372,
      url: KALEIDO_URL,
      accounts: {
        mnemonic: KALEIDO_MNEMONIC,
      },
      evmVersion: "byzantium",
    },

    coverage: {
      url: "http://localhost:8555",
    },
    kovan: {
      url: KOVAN_NODE_URL,
      accounts: {
        mnemonic: KOVAN_MNEMONIC || "",
      },
    },
    mainnet: {
      url: MAINNET_NODE_URL,
      accounts: {
        mnemonic: MAINNET_MNEMONIC,
      },
    },
  },
  solidity: {
    version: "0.6.11",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  solc: {
    version: "0.6.11",
    optimizer: {
      enabled: true,
      runs: 200,
    },
  },
  mocha: {
    timeout: 20000,
  },
};
