# BridgeAI

Cross-chain bridge with multi-relayer consensus on ProbeChain Rydberg Testnet.

## Features

- Lock tokens for cross-chain transfer
- Multi-relayer confirmation consensus
- Staked relayer registration
- Expired lock refunds
- Token claiming after confirmation

## Setup

```bash
npm install
cp .env.example .env
npx hardhat compile
npm run deploy
```

## Network

- **Network:** ProbeChain Rydberg Testnet
- **Chain ID:** 8004
- **RPC:** https://proscan.pro/chain/rydberg-rpc
