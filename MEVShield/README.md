# MEVShield

MEV protection via commit-reveal encrypted transaction submission on ProbeChain Rydberg Testnet.

## Features

- Submit encrypted transactions with commit hashes
- Reveal transactions within a time window
- Sequencer-based bundle execution
- Commit expiration for unrevealed transactions
- Prevents front-running and sandwich attacks

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
