# ProbeOracle2

Price oracle with TWAP support on ProbeChain Rydberg Testnet.

## Features

- Create price feeds with configurable heartbeat
- Authorized reporter price updates
- Feed-specific and global reporter authorization
- Latest price queries with stale detection
- Historical price lookups
- Time-Weighted Average Price (TWAP) calculation
- Heartbeat monitoring

## Setup

```bash
npm install
cp .env.example .env
# Edit .env with your private key
npx hardhat compile
npm run deploy
```

## Contract: PriceFeed

| Function | Description |
|---|---|
| `createFeed(pairName, heartbeat)` | Create price feed |
| `updatePrice(feedId, price, timestamp)` | Update price (reporter) |
| `getLatestPrice(feedId)` | Get latest price |
| `getHistoricalPrice(feedId, timestamp)` | Get historical price |
| `getTWAP(feedId)` | Get time-weighted average |

## Network

- **Network:** ProbeChain Rydberg Testnet
- **Chain ID:** 8004
- **RPC:** https://proscan.pro/chain/rydberg-rpc
