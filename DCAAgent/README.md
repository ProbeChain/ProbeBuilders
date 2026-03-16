# DCAAgent - Dollar-Cost Averaging Vault

Smart contract for automated dollar-cost averaging on ProbeChain Rydberg Testnet.

## Contract: DCAVault.sol

Users create recurring buy plans funded with native currency. Authorized keepers execute DCA cycles on schedule, simulating token purchases.

### Features
- **createPlan** - Create a DCA plan with token, amount per cycle, interval, and total cycles
- **executeDCA** - Keepers execute the next cycle for a plan
- **cancelPlan** - Cancel an active plan
- **withdrawFunds** - Withdraw remaining funds from cancelled/completed plans
- **Execution history** - Full per-plan execution tracking
- **Keeper management** - Owner authorizes keeper addresses

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
