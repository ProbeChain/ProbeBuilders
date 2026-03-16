# ProbePress

Decentralized publishing on ProbeChain Rydberg Testnet (Chain ID 8004).

## Features

- **Publish Articles** — Title, content hash, and configurable price.
- **Pay-per-Read** — Readers purchase individual article access.
- **Tipping** — Readers can tip authors on any article.
- **Subscriptions** — Authors set a monthly rate; subscribers access the full catalog.
- **Author Revenue** — Authors withdraw accumulated earnings minus platform fee.

## Contract

`PublishingPlatform.sol` — Solidity 0.8.24, EVM London, inline Ownable / ReentrancyGuard / Pausable.

## Quick Start

```bash
cp .env.example .env
npm install
npx hardhat compile
npx hardhat run scripts/deploy.ts --network rydberg
```

## Network

| Parameter | Value |
|-----------|-------|
| Network   | ProbeChain Rydberg Testnet |
| RPC       | https://proscan.pro/chain/rydberg-rpc |
| Chain ID  | 8004 |
| EVM       | London |
