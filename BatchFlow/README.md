# BatchFlow — Decentralized Batch Job Scheduler

Decentralized batch job scheduler on ProbeChain Rydberg Testnet (Chain ID 8004).

## Features

- Create batches of jobs with priority and deadline
- Workers claim and complete individual jobs
- Result submission with worker reputation tracking
- Budget distribution proportional to completed work

## Contract: BatchScheduler.sol

| Function | Description |
|---|---|
| `createBatch` | Create a funded batch of jobs |
| `claimJob` | Claim a job from a batch |
| `submitJobResult` | Submit result for claimed job |
| `finalizeBatch` | Finalize and distribute payments |
| `cancelBatch` | Cancel an open batch |

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
