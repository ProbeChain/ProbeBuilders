# MigrateAgent

Cross-chain contract migration tracker on ProbeChain Rydberg Testnet.

## Features

- Start cross-chain migration tracking
- Record individual migration steps with tx hashes
- Complete or cancel migrations
- Authorized agent system for automated migrations
- Full migration audit trail
- Migration status queries

## Setup

```bash
npm install
cp .env.example .env
# Edit .env with your private key
npx hardhat compile
npm run deploy
```

## Contract: MigrationTracker

| Function | Description |
|---|---|
| `startMigration(sourceChain, sourceContract, targetContract)` | Start migration |
| `recordStep(migrationId, stepName, status, txHash, notes)` | Record a step |
| `completeMigration(migrationId)` | Mark migration complete |
| `cancelMigration(migrationId)` | Cancel migration |
| `getMigrationStatus(migrationId)` | Get full status |

## Network

- **Network:** ProbeChain Rydberg Testnet
- **Chain ID:** 8004
- **RPC:** https://proscan.pro/chain/rydberg-rpc
