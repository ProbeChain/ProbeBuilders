# FHEVault — Encrypted Computation Escrow

Encrypted computation escrow with worker staking on ProbeChain Rydberg Testnet (Chain ID 8004).

## Features

- **Job Creation**: Requesters create computation jobs with encrypted inputs and rewards
- **Worker Staking**: Workers stake tokens as collateral to accept jobs
- **Result Submission**: Workers submit encrypted results with computation proofs
- **Dispute Resolution**: Owner-arbitrated disputes with stake slashing
- **Reputation System**: Worker reputation based on completed jobs vs disputes

## Contract: ComputeEscrow.sol

| Function | Description |
|---|---|
| `createJob` | Create a new computation job with reward |
| `acceptJob` | Worker accepts an open job |
| `submitResult` | Submit encrypted computation result |
| `approveResult` | Requester approves result, releasing payment |
| `disputeResult` | Requester disputes a submitted result |

## Setup

```bash
npm install
cp .env.example .env
# Add your private key to .env
npx hardhat compile
npx hardhat run scripts/deploy.ts --network rydberg
```

## Network

- **Network**: ProbeChain Rydberg Testnet
- **Chain ID**: 8004
- **RPC**: https://proscan.pro/chain/rydberg-rpc
- **EVM**: London
