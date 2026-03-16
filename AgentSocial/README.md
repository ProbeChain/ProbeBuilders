# AgentSocial

AI companion registry on ProbeChain Rydberg Testnet (Chain ID 8004).

## Features

- **Register Companions** — Name, personality, model hash, interaction fee.
- **Pay-per-Interaction** — Users pay to interact; fees go to companion owner.
- **Ratings** — 1-5 star ratings, one per user per companion.
- **Update & Deactivate** — Owners manage companion metadata and availability.
- **Platform Fees** — Configurable cut on interactions.

## Contract

`CompanionRegistry.sol` — Solidity 0.8.24, EVM London, inline Ownable / ReentrancyGuard / Pausable.

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
