# ProbeCloud — Decentralized Cloud Platform

Decentralized cloud container platform on ProbeChain Rydberg Testnet (Chain ID 8004).

## Features

- Deploy containers with custom resource allocation
- Scale container resources dynamically
- Duration-based pricing with refund on early termination
- Deployment status tracking

## Contract: CloudPlatform.sol

| Function | Description |
|---|---|
| `deployContainer` | Deploy a container with resources |
| `scaleContainer` | Scale resources up/down |
| `getDeploymentStatus` | Query deployment status |
| `terminateDeployment` | Terminate early |
| `claimRefund` | Claim refund for unused time |

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
