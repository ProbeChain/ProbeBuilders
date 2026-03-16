# ProbeStaking

Simple staking for ProbeChain Rydberg Testnet (Chain ID: 8004).

## Contract: SimpleStaking.sol

Stake native PROBE, earn fixed APR rewards, compound earnings.

### Key Functions
- `stake()` — Stake native PROBE (payable)
- `unstake(amount)` — Withdraw staked tokens
- `claimRewards()` — Claim accumulated rewards
- `compound()` — Compound rewards into stake
- `getStakeInfo(user)` — Get staking details

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
