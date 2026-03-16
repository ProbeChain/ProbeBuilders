# DocAgent

Documentation bounty platform for quality docs incentivization on ProbeChain Rydberg Testnet.

## Features

- Create funded documentation bounties with deadlines
- Submit documentation for open bounties
- Approve submissions with automatic escrow payout
- Reject inadequate submissions
- Cancel bounties with full refund
- Platform fee collection (2% default)
- Author reputation tracking

## Setup

```bash
npm install
cp .env.example .env
# Edit .env with your private key
npx hardhat compile
npm run deploy
```

## Contract: DocBounty

| Function | Description |
|---|---|
| `createDocBounty(topic, deadline)` | Create bounty (payable) |
| `submitDoc(bountyId, docHash)` | Submit documentation |
| `approveDoc(submissionId)` | Approve and pay bounty |
| `rejectDoc(submissionId)` | Reject submission |
| `cancelBounty(bountyId)` | Cancel and refund |

## Network

- **Network:** ProbeChain Rydberg Testnet
- **Chain ID:** 8004
- **RPC:** https://proscan.pro/chain/rydberg-rpc
