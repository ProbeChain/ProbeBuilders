# YieldFarm - LP Farming Manager

Smart contract for yield farming with per-second reward accrual on ProbeChain Rydberg Testnet.

## Contract: FarmManager.sol

Create farms, stake LP tokens, and earn reward tokens distributed per second.

### Features
- **createFarm** - Create a farm with LP token, reward token, rate, and duration
- **stake** - Stake LP tokens into a farm
- **withdraw** - Withdraw LP tokens (auto-claims pending rewards)
- **claimReward** - Claim accumulated rewards without withdrawing
- **Per-second accrual** - Rewards calculated precisely per second
- **Multiple farms** - Manage many farms from one contract

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
