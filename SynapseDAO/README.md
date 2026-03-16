# SynapseDAO

Conviction voting governance on ProbeChain Rydberg Testnet (Chain ID 8004).

## Features

- **Conviction Voting** — Longer token lock = higher vote multiplier (1x / 2x / 4x / 8x).
- **Stake with Lock** — Choose conviction level 0-3 (no lock, 7d, 30d, 90d).
- **Proposals** — Create proposals, vote with conviction-weighted power, execute on pass.
- **Quorum** — Configurable quorum threshold for proposal execution.

## Contract

`NeuralGovernance.sol` — Solidity 0.8.24, EVM London, inline Ownable / ReentrancyGuard / Pausable.

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
