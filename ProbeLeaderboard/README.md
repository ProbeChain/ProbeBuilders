# ProbeLeaderboard

Global leaderboard system on ProbeChain Rydberg Testnet (Chain ID: 8004).

## Contract: Leaderboard.sol

Create leaderboards, submit scores by authorized reporters, query rankings and top players.

### Key Functions
- `registerBoard(name, category, sortOrder)` -- Create a leaderboard
- `submitScore(boardId, player, score, proofHash)` -- Submit a score
- `getTopPlayers(boardId, count)` -- Get top N players
- `getPlayerRank(boardId, player)` -- Get a player's rank

### Deploy
```bash
cp .env.example .env
npm install
npx hardhat compile
npx hardhat run scripts/deploy.ts --network rydberg
```

## Network
- **Chain ID:** 8004
- **EVM:** London
- **Solidity:** 0.8.24
