# ProbeEsports

Esports tournament manager with single/double elimination and prize distribution on ProbeChain Rydberg Testnet.

## Features

- Create tournaments with configurable format (single/double elimination)
- Team registration with entry fees
- Match creation and result reporting
- Round advancement system
- Prize distribution (60/25/15 split)
- Tournament cancellation with refunds

## Contract: TournamentManager.sol

| Function | Description |
|----------|-------------|
| `createTournament(name, maxTeams, format)` | Create tournament (payable) |
| `registerTeam(tournamentId, teamName, members[])` | Register team (payable) |
| `reportMatch(matchId, winnerId)` | Report match result |
| `advanceRound(tournamentId)` | Advance to next round |
| `distributePrizes(tournamentId, 1st, 2nd, 3rd)` | Pay out prizes |

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
