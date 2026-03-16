# LootAgent

Contribution-weighted loot distribution for raid groups on ProbeChain Rydberg Testnet.

## Features

- Create raids with up to 40 participants
- Record DPS, healing, and tanking contributions
- Weighted contribution scoring (configurable weights)
- Fair ETH distribution based on contribution ratios
- Item distribution with round-robin allocation

## Contract: LootDistributor.sol

| Function | Description |
|----------|-------------|
| `createRaid(participants[], bossId)` | Create a new raid |
| `fundRaid(raidId)` | Fund the raid loot pool (payable) |
| `recordContribution(raidId, participant, dps, healing, tanking)` | Record contributions |
| `distributeLoot(raidId, itemIds[])` | Calculate and distribute shares |
| `claimShare(raidId)` | Claim your ETH share |

## Deployment

```bash
cp .env.example .env
npm install
npx hardhat compile
npx hardhat run scripts/deploy.ts --network rydberg
```

## Network

- **Network:** ProbeChain Rydberg Testnet
- **Chain ID:** 8004
- **RPC:** https://proscan.pro/chain/rydberg-rpc
- **EVM:** London
