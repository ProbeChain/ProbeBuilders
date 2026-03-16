# OracleAgent — Decentralized Oracle with Multi-Source Consensus

On-chain oracle system with median aggregation, outlier detection (2 std dev rejection), and reporter reputation tracking. Reporters stake to participate, earn reputation for accurate data.

## Contracts

- **OracleConsensus.sol** — Feed creation, data submission, median resolution, outlier detection, reporter management.

## Quick Start

```bash
npm install
cp .env.example .env
npx hardhat compile
npx hardhat run scripts/deploy.ts --network rydberg
```

## Key Functions

| Function | Description |
|---|---|
| `registerReporter()` | Stake to become a reporter |
| `createFeed(name, minReporters, timeout)` | Create data feed |
| `submitDataPoint(feedId, value)` | Submit a data point |
| `resolveFeed(feedId)` | Compute median, detect outliers |
| `getResolvedValue(feedId)` | Get final value |

## Network

- **Chain**: ProbeChain Rydberg Testnet
- **Chain ID**: 8004
- **RPC**: `https://proscan.pro/chain/rydberg-rpc`
