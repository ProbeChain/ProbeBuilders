# CollectorAgent

NFT collection analytics advisor on ProbeChain Rydberg Testnet (Chain ID: 8004).

## Contract: CollectionAdvisor.sol

Register collections, analyze floor prices, set alerts, get budget-based recommendations.

### Key Functions
- `registerCollection(nftContract)` -- Register a collection for tracking
- `analyzeFloor(collectionId)` -- Get floor price statistics
- `setAlert(collectionId, priceThreshold)` -- Set a price alert
- `getRecommendations(budget, riskLevel)` -- Get buy recommendations

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
