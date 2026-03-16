# ProbeIndex

Blockchain indexer registry for discovering and subscribing to data indexers on ProbeChain Rydberg Testnet.

## Features

- Register indexers with supported event types
- Paid subscriptions to indexers
- Data reporting with block range and hash verification
- Indexer discovery and listing

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
