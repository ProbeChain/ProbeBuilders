# ProbeReward

Universal reward distributor for ProbeChain Rydberg Testnet (Chain ID: 8004).

## Contract: RewardDistributor.sol

Multiple concurrent reward pools with staking, time-based accumulation, and claiming.

### Key Functions
- `createPool(rewardToken, rewardRate, duration)` — Create a reward pool
- `stake(poolId, amount)` — Stake into a pool
- `withdraw(poolId, amount)` — Withdraw staked tokens
- `claimReward(poolId)` — Claim accumulated rewards

## Setup
```bash
npm install
cp .env.example .env
npx hardhat compile
npm run deploy
```

## Network
- **Chain ID:** 8004
- **EVM:** London
- **Solidity:** 0.8.24
