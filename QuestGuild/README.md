# QuestGuild

Cross-game quest aggregator with completion tracking and reward distribution on ProbeChain Rydberg Testnet.

## Features

- Register multiple game contracts as quest sources
- Publish quests with rewards and expiry dates
- Aggregate available quests per user across all games
- Track quest completions with on-chain records
- Batch claim rewards for all completed quests

## Contract: QuestAggregator.sol

| Function | Description |
|----------|-------------|
| `registerQuestSource(sourceContract, gameName)` | Register a game as quest source |
| `publishQuest(sourceId, title, descHash, reward, expiry)` | Publish a new quest |
| `aggregateQuests(user)` | Get available quests for a user |
| `trackCompletion(user, questId)` | Record quest completion |
| `claimAggregateRewards()` | Claim all unclaimed rewards |

## Deployment

```bash
cp .env.example .env
# Edit .env with your private key
npm install
npx hardhat compile
npx hardhat run scripts/deploy.ts --network rydberg
```

## Network

- **Network:** ProbeChain Rydberg Testnet
- **Chain ID:** 8004
- **RPC:** https://proscan.pro/chain/rydberg-rpc
- **EVM:** London
