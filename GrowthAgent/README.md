# GrowthAgent

On-chain growth metrics tracking and comparison on ProbeChain Rydberg Testnet.

## Features

- Register projects with category classification
- Record time-series metrics (Users, Transactions, Volume, Revenue, TVL)
- Calculate growth rates in basis points
- Compare metrics across multiple projects
- Authorized reporter system
- Metric history retrieval

## Setup

```bash
npm install
cp .env.example .env
# Edit .env with your private key
npx hardhat compile
npm run deploy
```

## Contract: GrowthTracker

| Function | Description |
|---|---|
| `registerProject(name, category)` | Register project |
| `recordMetric(projectId, metricType, value, timestamp)` | Record metric |
| `getGrowthRate(projectId, metricType)` | Get growth rate |
| `compareProjects(ids[], metricType)` | Compare projects |
| `getMetricHistory(projectId, metricType, limit)` | Get history |

## Network

- **Network:** ProbeChain Rydberg Testnet
- **Chain ID:** 8004
- **RPC:** https://proscan.pro/chain/rydberg-rpc
