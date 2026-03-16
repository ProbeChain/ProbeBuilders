# ProbeLocker

Token lock supporting ERC-20 and native PROBE with time-based unlocking on ProbeChain Rydberg Testnet.

## Features

- Lock ERC-20 tokens or native PROBE
- Time-based unlock mechanism
- Extend lock duration
- Fee-on-transfer token support
- Track locked balances per token

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
