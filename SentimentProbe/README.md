# SentimentProbe - Market Sentiment Oracle

Decentralized market sentiment oracle with reputation-weighted scoring on ProbeChain Rydberg Testnet.

## Features

- **Sentiment Feeds**: Create feeds for any market/topic (e.g., "BTC Sentiment", "DeFi Fear Index")
- **Reporter Staking**: Stake native tokens to become a sentiment reporter
- **Reputation System**: 0-1000 reputation that weights score contributions
- **Weighted Aggregation**: Final sentiment = reputation-weighted average of all submissions
- **Cooldown System**: 5-minute cooldown between submissions per feed per reporter

## Contract: SentimentOracle.sol

| Function | Description |
|----------|-------------|
| `createFeed(name, description)` | Create a sentiment feed |
| `stakeAsReporter()` | Stake to become reporter |
| `submitSentiment(feedId, score, confidence)` | Submit score (-100 to +100) |
| `getSentiment(feedId)` | Get weighted average sentiment |
| `adjustReputation(reporter, rep)` | Adjust reputation (owner) |

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
