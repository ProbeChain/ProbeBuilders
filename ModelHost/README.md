# ModelHost — Decentralized Model Serving

Decentralized model serving platform on ProbeChain Rydberg Testnet (Chain ID 8004).

## Features

- Host models with staking requirement
- Pay-per-call inference with escrow
- Response submission and dispute resolution
- Timeout-based refunds for unresponsive hosts

## Contract: ModelServing.sol

| Function | Description |
|---|---|
| `hostModel` | Host a model with stake |
| `callModel` | Call a model with payment |
| `submitResponse` | Submit inference response |
| `disputeResponse` | Dispute a response |
| `deactivateModel` | Deactivate and reclaim stake |

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
