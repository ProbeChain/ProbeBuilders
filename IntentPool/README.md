# IntentPool

Intent aggregation and batch execution on ProbeChain Rydberg Testnet (Chain ID: 8004).

## Contract: IntentAggregator.sol

Aggregate multiple user intents into batches for gas-efficient solver execution.

### Key Functions
- `submitIntent(intentType, params, maxCost)` payable -- Submit an intent
- `batchIntents(intentIds[])` -- Batch pending intents together
- `executeBatch(batchId, solution)` -- Solver executes a batch
- `settleBatch(batchId)` -- Settle and distribute payments

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
