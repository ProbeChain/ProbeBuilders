// ProbeChain Rydberg Testnet Network Configuration
// Chain ID: 8004 | EVM London-compatible | ~1s block time

export const RYDBERG_RPC = "https://proscan.pro/chain/rydberg-rpc";
export const CHAIN_ID = 8004;
export const EXPLORER_URL = "https://proscan.pro/rydberg";

export const networkConfig = {
  rydberg: {
    url: RYDBERG_RPC,
    chainId: CHAIN_ID,
    accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
    gasPrice: 1000000000, // 1 gwei
  },
};
