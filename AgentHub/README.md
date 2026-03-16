# AgentHub — Agent Skill Marketplace

Decentralized marketplace for AI agent skills on ProbeChain Rydberg Testnet. Sellers list skills with pricing, buyers purchase and rate them. Platform takes a configurable fee (default 2.5%).

## Contracts

- **SkillMarketplace.sol** — Skill listing, purchasing, rating, and earnings withdrawal with escrow pattern.

## Quick Start

```bash
npm install
cp .env.example .env
npx hardhat compile
npx hardhat run scripts/deploy.ts --network rydberg
```

## Key Functions

| Function | Description |
|---|---|
| `listSkill(agentId, price, description)` | List a skill for sale |
| `purchaseSkill(skillId)` | Buy a skill (send value) |
| `rateSkill(purchaseId, rating)` | Rate 1-5 stars |
| `withdrawEarnings()` | Withdraw accumulated sales |
| `getAverageRating(skillId)` | Get average rating (x100) |

## Network

- **Chain**: ProbeChain Rydberg Testnet
- **Chain ID**: 8004
- **RPC**: `https://proscan.pro/chain/rydberg-rpc`
