# TensorPool — Decentralized Training Cluster

Decentralized ML training cluster on ProbeChain Rydberg Testnet (Chain ID 8004).

## Features

- Create funded training jobs with model/dataset hashes
- Contributors join pools with GPU resources
- Submit training results with loss scores
- Verify results and distribute rewards proportionally

## Contract: TrainingPool.sol

| Function | Description |
|---|---|
| `createTrainingJob` | Create a funded training job |
| `joinPool` | Join with GPU resources |
| `submitResult` | Submit trained weights |
| `verifyResult` | Verify and complete job |
| `claimReward` | Claim reward share |

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
