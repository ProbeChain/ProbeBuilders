# IntentForge

Intent compiler and solver marketplace on ProbeChain Rydberg Testnet (Chain ID: 8004).

## Contract: IntentEngine.sol

Submit user intents, solvers propose execution plans, execute and settle with dispute resolution.

### Key Functions
- `submitIntent(userIntent, maxGas, deadline)` payable -- Submit an intent
- `solveIntent(intentId, executionPlan)` -- Solver proposes solution
- `executeIntent(intentId)` -- Execute a solved intent
- `disputeSolution(intentId, reasonHash)` -- Dispute a solution

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
