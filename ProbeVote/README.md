# ProbeVote — Anonymous Commit-Reveal Voting

Two-phase voting system that prevents front-running. Voters first commit a hash of their vote, then reveal it after the commit phase ends. Results are tallied only after all reveals.

## Contracts

- **CommitRevealVote.sol** — Poll creation, commit phase, reveal phase, tally, and cancellation.

## Quick Start

```bash
npm install
cp .env.example .env
npx hardhat compile
npx hardhat run scripts/deploy.ts --network rydberg
```

## How It Works

1. **Create Poll**: `createPoll(question, options, commitDuration, revealDuration)`
2. **Commit Phase**: Voters submit `commitVote(pollId, keccak256(pollId, optionId, salt))`
3. **Reveal Phase**: Voters reveal `revealVote(pollId, optionId, salt)`
4. **Tally**: Anyone calls `tallyResults(pollId)` after reveal ends

## Key Functions

| Function | Description |
|---|---|
| `createPoll(question, options, commitDur, revealDur)` | Create poll |
| `commitVote(pollId, hashedVote)` | Commit hashed vote |
| `revealVote(pollId, optionId, salt)` | Reveal vote |
| `tallyResults(pollId)` | Compute final results |
| `computeCommitHash(pollId, optionId, salt)` | Helper to compute hash |

## Network

- **Chain**: ProbeChain Rydberg Testnet
- **Chain ID**: 8004
- **RPC**: `https://proscan.pro/chain/rydberg-rpc`
