# DAOVoice

Weighted governance on ProbeChain Rydberg Testnet (Chain ID 8004).

## Features

- **Stake for Voting Power** — Stake native tokens; power = staked amount * reputation multiplier.
- **Reputation System** — Owner-assigned multiplier (100 = 1x, 200 = 2x).
- **Proposals with Actions** — Encode on-chain calls that execute on passing.
- **Weighted Voting** — Commit partial or full voting power.
- **Quorum & Execution** — Configurable quorum; auto-finalize on execution.

## Contract

`WeightedGovernor.sol` — Solidity 0.8.24, EVM London, inline Ownable / ReentrancyGuard / Pausable.

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
