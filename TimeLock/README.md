# TimeLock

Timelock controller with proposer/executor roles and min/max delay constraints on ProbeChain Rydberg Testnet.

## Features

- Schedule operations with configurable delays
- Proposer and executor role separation
- Min/max delay constraints
- Cancel pending operations
- Operation status tracking

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
