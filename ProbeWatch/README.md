# ProbeWatch

Surveillance data marketplace on ProbeChain Rydberg Testnet (Chain ID: 8004).

## Contract: SurveillanceMarket.sol

Register cameras, subscribe to feeds, report anomalies, and earn detection rewards.

### Key Functions
- `registerCamera(location, resolution, coverage)` -- Register a camera
- `subscribeFeed(cameraId, duration)` payable -- Subscribe to a feed
- `reportAnomaly(cameraId, anomalyHash, timestamp)` -- Report anomaly
- `claimReward()` -- Claim anomaly detection rewards

### Deploy
```bash
cp .env.example .env
npm install
npx hardhat compile
npx hardhat run scripts/deploy.ts --network rydberg
```

## Network
- **Chain ID:** 8004
- **EVM:** London
- **Solidity:** 0.8.24
