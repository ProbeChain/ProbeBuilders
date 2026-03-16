# LiquidBot

Liquidation bot engine for ProbeChain Rydberg Testnet (Chain ID 8004).

## Contract: LiquidationEngine

- **monitorPosition(protocol, user, collateral, debt)** — Register a position for monitoring.
- **executeLiquidation(positionId, repayAmount)** — Keepers liquidate under-collateralized positions and earn a 5% bonus.
- **claimBonus()** — Keepers withdraw accumulated bonuses.
- Keeper registration and incentive system.

## Setup

```bash
npm install
cp .env.example .env
# Add your private key to .env
npx hardhat compile
npx hardhat run scripts/deploy.ts --network rydberg
```
