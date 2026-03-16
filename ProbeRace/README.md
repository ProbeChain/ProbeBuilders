# ProbeRace

On-chain racing game with leaderboard and season tracking on ProbeChain Rydberg Testnet.

## Features

- Create races with configurable tracks, entry fees, and max racers
- Oracle-submitted race results with proof hashes
- Automatic prize distribution with platform fee
- Per-season leaderboard tracking (wins, best times, earnings)
- Season advancement by owner

## Contract: RaceTrack.sol

| Function | Description |
|----------|-------------|
| `createRace(trackId, entryFee, maxRacers)` | Create a new race |
| `joinRace(raceId)` | Join a race (payable) |
| `submitResult(raceId, racer, finishTime, proofHash)` | Oracle submits result |
| `finalizeRace(raceId)` | Oracle finalizes the race |
| `claimPrize(raceId)` | Winner claims prize |
| `advanceSeason()` | Owner advances the season |

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
