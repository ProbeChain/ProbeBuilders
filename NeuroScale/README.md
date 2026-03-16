# NeuroScale — Auto-Scaling Inference

Auto-scaling inference endpoint manager on ProbeChain Rydberg Testnet (Chain ID 8004).

## Features

- Register inference endpoints with RPS capacity
- Request auto-scaling with tracked history
- Pay-per-request inference processing
- Timeout-based refunds for expired requests

## Contract: AutoScaler.sol

| Function | Description |
|---|---|
| `registerEndpoint` | Register an inference endpoint |
| `requestScale` | Request scaling to target RPS |
| `processRequest` | Submit an inference request |
| `submitResponse` | Respond with output |
| `claimExpired` | Reclaim timed-out payments |

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
