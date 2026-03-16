# ProbeSwapRouter

DEX aggregator router that splits orders across multiple pools for ProbeChain Rydberg Testnet.

## Features

- Multi-pool price comparison via `getQuotes` and `getBestQuote`
- Single-pool best-price routing via `swapBestPool`
- Split order execution across up to 5 pools
- Configurable aggregator fee (default 0.05%)
- Pool registration management

## Contracts

| Contract | Address |
|---|---|
| AggregatorRouter | `TBD` |

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
