# ProbeGraph

On-chain relationship analytics and graph on ProbeChain Rydberg Testnet (Chain ID: 8004).

## Contract: GraphAnalytics.sol

Register entities, record typed relationships, query connections and explore clusters.

### Key Functions
- `registerEntity(entityType, dataHash)` -- Register an entity
- `recordRelationship(entity1, entity2, relationType, metadata)` -- Record a relationship
- `queryRelationships(entityId)` -- Get all relationships for an entity
- `getCluster(entityId, depth)` -- Get connected entity cluster

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
