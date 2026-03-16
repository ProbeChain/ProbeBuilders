# DungeonAI

On-chain dungeon crawler game for ProbeChain Rydberg Testnet (Chain ID: 8004).

## Contract: DungeonCrawler.sol

Players explore dungeons with pseudo-random encounters, action choices, and loot rewards.

### Key Functions
- `createDungeon(difficulty, rooms, rewards)` — Create a dungeon
- `enterDungeon(dungeonId)` — Enter a dungeon (pay entry fee)
- `exploreRoom(dungeonId, roomId, actionChoice)` — Explore a room
- `claimLoot(dungeonId)` — Claim loot after completing

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
