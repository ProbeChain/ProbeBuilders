# ProbeLend

Lending protocol with 150% collateralization for ProbeChain Rydberg Testnet.

## Features

- Multi-market lending pool with deposit, borrow, repay, liquidate
- 150% collateral ratio with 5% liquidation bonus
- Accruing interest model (~1% APR)
- Owner-controlled price oracle
- Cross-collateral health factor checking

## Contracts

| Contract | Address |
|---|---|
| LendingPool | `TBD` |

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
