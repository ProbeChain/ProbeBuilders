# TaxBot - DeFi Tax Tracking Ledger

Smart contract for immutable DeFi tax record keeping on ProbeChain Rydberg Testnet.

## Contract: TaxLedger.sol

Record trades and income events on-chain for a tamper-proof audit trail. Generate annual summary report hashes.

### Features
- **recordTrade** - Record a trade with tx hash, assets, amounts, and timestamp
- **recordIncome** - Record income from staking, farming, airdrops, etc.
- **generateReport** - Generate an annual summary hash covering all year's records
- **Immutable audit trail** - All records are permanent and timestamped
- **Authorized recorders** - Delegate recording to bots/relayers

## Network
- **Chain**: ProbeChain Rydberg Testnet
- **Chain ID**: 8004
- **RPC**: https://proscan.pro/chain/rydberg-rpc

## Setup
```bash
npm install
cp .env.example .env
# Edit .env with your private key
npm run compile
npm run deploy
```
