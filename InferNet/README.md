# InferNet — Decentralized Inference Network

Decentralized AI inference network on ProbeChain Rydberg Testnet (Chain ID 8004).

## Features

- Register AI models with pricing and specs
- Request inference with payment escrow
- Submit results with computation proofs
- Dispute resolution with timeout mechanism

## Contract: InferenceNetwork.sol

| Function | Description |
|---|---|
| `registerModel` | Register an AI model |
| `requestInference` | Request inference with payment |
| `submitResult` | Submit result with proof |
| `verifyAndPay` | Release payment to provider |
| `disputeResult` | Dispute a result |

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
