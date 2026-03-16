# ProbeGPU — GPU Rental Marketplace

Decentralized GPU rental marketplace on ProbeChain Rydberg Testnet (Chain ID 8004).

## Features

- Register GPUs with model specs and pricing
- Rent GPUs by the hour
- Return GPUs and rate providers
- Claim earnings with platform fee

## Contract: GPUMarketplace.sol

| Function | Description |
|---|---|
| `registerGPU` | Register a GPU for rental |
| `rentGPU` | Rent a GPU |
| `returnGPU` | Return a rented GPU |
| `rateProvider` | Rate a provider (1-5) |
| `claimEarnings` | Withdraw earnings |

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
