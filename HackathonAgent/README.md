# HackathonAgent

Decentralized hackathon platform on ProbeChain Rydberg Testnet.

## Features

- Create funded hackathons with prize pools
- Team registration with member lists
- Project submission with deadline enforcement
- Multi-judge scoring system (0-100)
- Prize distribution to winners
- Full lifecycle management (Registration, Active, Judging, Completed)

## Setup

```bash
npm install
cp .env.example .env
# Edit .env with your private key
npx hardhat compile
npm run deploy
```

## Contract: HackathonManager

| Function | Description |
|---|---|
| `createHackathon(name, maxTeams, deadline)` | Create hackathon (payable) |
| `registerTeam(hackathonId, name, members[])` | Register team |
| `submitProject(hackathonId, projectHash)` | Submit project |
| `judgeProject(hackathonId, teamId, score)` | Judge project |
| `distributePrizes(hackathonId, winnerTeamId)` | Distribute prizes |

## Network

- **Network:** ProbeChain Rydberg Testnet
- **Chain ID:** 8004
- **RPC:** https://proscan.pro/chain/rydberg-rpc
