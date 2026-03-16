# ProbeChess2

Advanced chess tournament with Swiss-system pairing and Buchholz tiebreakers on ProbeChain Rydberg Testnet.

## Features

- Create tournaments with configurable entry fee, player cap, and round count
- Swiss-system pairing (players matched by score, no rematches)
- Three match results: WhiteWins, BlackWins, Draw
- Buchholz tiebreaker calculation (sum of opponents' scores)
- Prize distribution: 50% / 30% / 20% for top 3
- Platform fee on prize pool

## Contract: ChessTournament.sol

| Function | Description |
|----------|-------------|
| `createTournament(entryFee, maxPlayers, rounds)` | Create tournament (payable) |
| `register(tournamentId)` | Register for tournament (payable) |
| `createMatch(tournamentId, white, black)` | Create a Swiss-paired match |
| `reportResult(matchId, result)` | Report match result |
| `advanceRound(tournamentId)` | Advance to next round |
| `claimPrize(tournamentId, 1st, 2nd, 3rd)` | Distribute prizes |

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
