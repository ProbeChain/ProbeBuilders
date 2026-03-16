# GoldReserve

Gold reserve tracker for ProbeChain Rydberg Testnet (Chain ID: 8004).

## Contract: GoldReserveTracker.sol

Tracks ProbeChain's gold reserve with verified updates, decay calculations, and reward multipliers.

### Key Functions
- `updateReserve(totalOZ, verifierSignature, timestamp)` — Update reserve data
- `getReserve()` — Get current reserve (totalOZ, lastUpdate)
- `calculateDecay(currentOZ, targetOZ)` — Calculate decay between current and target
- `getRewardMultiplier()` — Get reward multiplier based on reserve health

## Setup
```bash
npm install
cp .env.example .env
npx hardhat compile
npm run deploy
```

## Network
- **Chain ID:** 8004
- **EVM:** London
- **Solidity:** 0.8.24
