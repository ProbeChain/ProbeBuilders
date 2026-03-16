# BugBountyAgent

Decentralized bug bounty platform on ProbeChain Rydberg Testnet.

## Features

- Create funded bug bounty programs with scope and max reward
- Submit bugs with severity levels (Info, Low, Medium, High, Critical)
- Triage bugs with accept/reject and reward assignment
- Automated bounty payouts
- Reporter reputation tracking
- Program funding and closure

## Setup

```bash
npm install
cp .env.example .env
# Edit .env with your private key
npx hardhat compile
npm run deploy
```

## Contract: BugBountyPlatform

| Function | Description |
|---|---|
| `createProgram(name, scope, maxReward)` | Create program (payable) |
| `submitBug(programId, severity, reportHash)` | Submit bug report |
| `triageBug(bugId, accepted, reward)` | Triage a bug |
| `payBounty(bugId)` | Pay accepted bug bounty |
| `closeProgram(programId)` | Close and withdraw |

## Network

- **Network:** ProbeChain Rydberg Testnet
- **Chain ID:** 8004
- **RPC:** https://proscan.pro/chain/rydberg-rpc
