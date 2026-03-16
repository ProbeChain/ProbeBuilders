import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import * as dotenv from "dotenv";

dotenv.config();

const PRIVATE_KEY = process.env.PRIVATE_KEY || "0x" + "0".repeat(64);
const RPC_URL = process.env.PROBE_RPC_URL || "https://rpc-rydberg.probechain.org";

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.24",
    settings: {
      optimizer: { enabled: true, runs: 200 },
      evmVersion: "london",
    },
  },
  networks: {
    probeRydberg: {
      url: RPC_URL,
      chainId: 8004,
      accounts: [PRIVATE_KEY],
    },
  },
};

export default config;
