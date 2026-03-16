# BandwidthX — Bandwidth Sharing Exchange

Decentralized bandwidth sharing marketplace on ProbeChain Rydberg Testnet (Chain ID 8004).

## Features

- Register as a bandwidth provider with pricing
- Purchase bandwidth sessions
- Usage tracking and reporting
- Fair settlement with refunds for unused bandwidth

## Contract: BandwidthExchange.sol

| Function | Description |
|---|---|
| `registerProvider` | Register as a bandwidth provider |
| `purchaseBandwidth` | Buy bandwidth from a provider |
| `reportUsage` | Report session usage in bytes |
| `settleSession` | Settle and distribute payment |
| `withdraw` | Withdraw earnings |

## Quick Start

```bash
cp .env.example .env
# Add your private key to .env
npm install
npx hardhat compile
npx hardhat run scripts/deploy.ts --network rydberg
```

## Network

- **Network:** ProbeChain Rydberg Testnet
- **Chain ID:** 8004
- **RPC:** https://proscan.pro/chain/rydberg-rpc
