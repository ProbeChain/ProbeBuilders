# ProbeStake

Staking optimizer with auto-compound and validator delegation for ProbeChain Rydberg Testnet.

## Features

- Stake/unstake with cooldown period (default 3 days)
- Per-second reward accrual
- Validator delegation with commission system
- Auto-compound function for keeper bots
- Validator management (add, activate/deactivate)

## Contracts

| Contract | Address |
|---|---|
| StakeOptimizer | `TBD` |

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
