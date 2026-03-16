# ProbeMap

Decentralized mapping and POI contributions on ProbeChain Rydberg Testnet (Chain ID: 8004).

## Contract: MapContributions.sol

Submit locations with geo coordinates, verify through trusted verifiers, earn rewards.

### Key Functions
- `submitLocation(lat, long, poiType, dataHash)` -- Submit a POI
- `verifyLocation(locationId)` -- Verifier confirms a location
- `getLocationsInArea(lat, long, radius)` -- Query nearby locations
- `rewardContributor()` -- Claim contributor rewards

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
