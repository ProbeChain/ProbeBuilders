# BountyBoard — Decentralized Bounty Platform

Create bounties with escrowed rewards, submit work with proof hashes, approve payouts or dispute outcomes. Supports deadline enforcement, cancellation, and admin dispute resolution.

## Contracts

- **BountyBoard.sol** — Bounty creation, work submission, approval, dispute, cancellation, expiration.

## Quick Start

```bash
npm install
cp .env.example .env
npx hardhat compile
npx hardhat run scripts/deploy.ts --network rydberg
```

## Key Functions

| Function | Description |
|---|---|
| `createBounty(description, deadline)` | Create bounty (send reward as value) |
| `submitWork(bountyId, proofHash, proofURI)` | Submit work |
| `approveBounty(bountyId, submissionId)` | Approve and pay winner |
| `disputeBounty(bountyId, reason)` | Dispute outcome |
| `cancelBounty(bountyId)` | Cancel (before submissions) |

## Network

- **Chain**: ProbeChain Rydberg Testnet
- **Chain ID**: 8004
- **RPC**: `https://proscan.pro/chain/rydberg-rpc`
