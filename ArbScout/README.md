# ArbScout

Arbitrage execution contract with profit tracking for ProbeChain Rydberg Testnet.

## Features

- Multi-hop circular arbitrage execution
- Split arbitrage across two DEX routers
- Flash loan callback interface (Aave-compatible)
- Profit tracking and trade history
- Whitelisted router system
- Owner-only execution for security

## Contracts

| Contract | Address |
|---|---|
| ArbExecutor | `TBD` |

## Quick Start

```bash
cp .env.example .env
npm install
npx hardhat compile
npx hardhat run scripts/deploy.ts --network rydberg
```

## Network

- RPC: `https://proscan.pro/chain/rydberg-rpc`
- Chain ID: `8004`
