# TokenRadar - New Token Risk Scoring

Crowd-sourced token risk assessment with auditor staking and slashing on ProbeChain Rydberg Testnet.

## Features

- **Score Requests**: Anyone can request a risk score for a token (with bounty)
- **Auditor Staking**: Stake tokens to become an auditor eligible to submit scores
- **Risk Scoring**: Auditors submit scores 0-100 (0 = max risk, 100 = safe) with report hashes
- **Auto-Finalization**: Scores auto-finalize after minimum submissions; bounty split among auditors
- **Slashing**: Owner can slash dishonest auditors (10% stake penalty + reputation loss)

## Contract: TokenScorer.sol

| Function | Description |
|----------|-------------|
| `requestScore(tokenAddress)` | Request risk score (payable bounty) |
| `stakeAsAuditor()` | Stake to become auditor |
| `submitScore(requestId, score, reportHash)` | Submit a risk score |
| `getTokenScore(tokenAddress)` | Get aggregated score |
| `slashAuditor(auditor, reason)` | Slash dishonest auditor |

## Quick Start

```bash
cp .env.example .env
npm install
npx hardhat compile
npx hardhat run scripts/deploy.ts --network rydberg
```

## Network

- **Network**: ProbeChain Rydberg Testnet
- **Chain ID**: 8004
- **RPC**: https://proscan.pro/chain/rydberg-rpc
