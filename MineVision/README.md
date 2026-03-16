# MineVision — Mining Production Monitor

Mining production monitoring and verification on ProbeChain Rydberg Testnet (Chain ID 8004).

## Features

- Register mines with mineral type and location
- Report production data with quality grades
- Auditor verification of production reports
- Paginated production history

## Contract: MineMonitor.sol

| Function | Description |
|---|---|
| `registerMine` | Register a mine |
| `reportProduction` | Report production data |
| `verifyProduction` | Auditor verifies a report |
| `getProductionHistory` | Query production history |

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
