# ChainLogger

Immutable event logging system on ProbeChain Rydberg Testnet (Chain ID: 8004).

## Contract: EventLogger.sol

Log events by category and severity (Info/Warning/Error/Critical), subscribe to categories.

### Key Functions
- `logEvent(category, severity, message, dataHash)` -- Log an event
- `getEvents(category, fromBlock, toBlock)` -- Query events in range
- `subscribeToCategory(category)` payable -- Subscribe to notifications
- `batchLogEvents(...)` -- Log multiple events at once

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
