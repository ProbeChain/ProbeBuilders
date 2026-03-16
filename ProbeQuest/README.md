# ProbeQuest - On-Chain RPG Quest System

On-chain RPG quest system deployed on ProbeChain Rydberg Testnet (Chain ID 8004).

## Features

- **Character Creation**: Create characters with 4 classes (Warrior, Mage, Ranger, Healer) each with unique stat distributions
- **Quest System**: Owner creates quests with difficulty levels (1-10), XP rewards, token rewards, level requirements, and prerequisites
- **XP & Leveling**: Characters earn XP from quests, auto-level up every 100 XP, stat boosts on level up
- **Proof-of-Completion**: Quests require on-chain proof hash for verification
- **Token Rewards**: Completed quests award native token rewards from the contract balance

## Contract: RPGQuest.sol

| Function | Description |
|----------|-------------|
| `createCharacter(name, class)` | Create a character (one per address) |
| `createQuest(...)` | Owner creates a quest with params |
| `acceptQuest(questId)` | Accept an available quest |
| `completeQuest(questId, proofHash)` | Complete quest with proof |
| `claimReward(questId)` | Claim native token reward |

## Quick Start

```bash
cp .env.example .env
# Edit .env with your private key
npm install
npx hardhat compile
npx hardhat run scripts/deploy.ts --network rydberg
```

## Network

- **Network**: ProbeChain Rydberg Testnet
- **Chain ID**: 8004
- **RPC**: https://proscan.pro/chain/rydberg-rpc
