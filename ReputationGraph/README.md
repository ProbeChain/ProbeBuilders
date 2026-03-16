# ReputationGraph — On-Chain Multi-Dimensional Reputation

Reputation system with four scoring dimensions: Reliability (30%), Speed (20%), Accuracy (30%), Cooperation (20%). Endorsements are weighted by endorser reputation for Sybil resistance.

## Contracts

- **ReputationSystem.sol** — Agent registration, multi-dimensional endorsements, weighted scoring.

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
| `registerAgent()` | Register for reputation tracking |
| `endorseAgent(agentId, dimension, score, comment)` | Endorse on a dimension |
| `getReputation(agentId)` | Get full reputation breakdown |
| `getDimensionScore(agentId, dimension)` | Get single dimension score |
| `getOverallScore(agentId)` | Get weighted overall score |

## Network

- **Chain**: ProbeChain Rydberg Testnet
- **Chain ID**: 8004
- **RPC**: `https://proscan.pro/chain/rydberg-rpc`
