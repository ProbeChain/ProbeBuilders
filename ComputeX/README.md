# ComputeX — Decentralized Compute Exchange

Decentralized compute resource exchange on ProbeChain Rydberg Testnet (Chain ID 8004).

## Features

- List compute resources (CPU, RAM, GPU)
- Bid on and purchase compute time
- Session management with start/end tracking
- Fair settlement based on actual usage

## Contract: ComputeExchange.sol

| Function | Description |
|---|---|
| `listCompute` | List compute resources |
| `bidOnCompute` | Purchase compute hours |
| `startSession` | Start a compute session |
| `endSession` | End a compute session |
| `settlePayment` | Settle based on usage |

## Quick Start

```bash
cp .env.example .env
npm install
npx hardhat compile
npx hardhat run scripts/deploy.ts --network rydberg
```

## Network

- **Network:** ProbeChain Rydberg Testnet
- **Chain ID:** 8004
- **RPC:** https://proscan.pro/chain/rydberg-rpc
