# MentorMatch

Decentralized mentorship matching platform on ProbeChain Rydberg Testnet.

## Features

- Register as mentor with skills and hourly rate
- Request mentorship by skill with budget escrow
- Accept mentorship requests
- Dual-confirmation completion with payout
- Mentor rating system (1-5 stars)
- Skill-based mentor discovery
- Platform fee collection

## Setup

```bash
npm install
cp .env.example .env
# Edit .env with your private key
npx hardhat compile
npm run deploy
```

## Contract: MentorPlatform

| Function | Description |
|---|---|
| `registerMentor(skills[], hourlyRate)` | Register as mentor |
| `requestMentor(skill)` | Request mentor (payable) |
| `acceptMentorship(requestId)` | Accept request |
| `completeMentorship(mentorshipId)` | Confirm completion |
| `rateMentor(mentorAddr, score)` | Rate mentor |

## Network

- **Network:** ProbeChain Rydberg Testnet
- **Chain ID:** 8004
- **RPC:** https://proscan.pro/chain/rydberg-rpc
