# MEVWatch

MEV activity monitor and registry for ProbeChain Rydberg Testnet (Chain ID 8004).

## Contract: MEVRegistry

- **registerWatcher()** payable — Stake to become a MEV watcher.
- **reportMEV(txHash, mevType, extractedValue, victimTx)** — Report observed MEV activity.
- **getMEVStats(startBlock, endBlock)** — Query aggregated MEV stats for a block range.
- **slashFalseReport(reportId)** — Owner slashes false reporters.
- **claimRewards()** — Watchers claim accumulated rewards.
- MEV types: Sandwich, Frontrun, Backrun, Arbitrage.

## Setup

```bash
npm install
cp .env.example .env
# Add your private key to .env
npx hardhat compile
npx hardhat run scripts/deploy.ts --network rydberg
```
