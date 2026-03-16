// Base Hardhat configuration shared by all ProbeBuilders DApps
// Usage: import and spread in each DApp's hardhat.config.ts

import { HardhatUserConfig } from "hardhat/config";

export const baseConfig: Partial<HardhatUserConfig> = {
  solidity: {
    version: "0.8.24",
    settings: {
      optimizer: { enabled: true, runs: 200 },
      evmVersion: "london",
    },
  },
  networks: {
    rydberg: {
      url: "https://proscan.pro/chain/rydberg-rpc",
      chainId: 8004,
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
    },
    localhost: {
      url: "http://127.0.0.1:8545",
    },
  },
};
