# StakeRouter

Multi-validator staking router for ProbeChain Rydberg Testnet (Chain ID 8004).

## Contract: StakeRouter

- **delegateStake(validators[], amounts[])** — Delegate stake across multiple validators in one transaction.
- **undelegateStake(validator, amount)** — Withdraw delegation from a validator.
- **rebalance(from, to, amount)** — Move stake between validators.
- **compoundRewards(validator)** — Claim and re-delegate proportional rewards.

## Setup

```bash
npm install
cp .env.example .env
# Add your private key to .env
npx hardhat compile
npx hardhat run scripts/deploy.ts --network rydberg
```
