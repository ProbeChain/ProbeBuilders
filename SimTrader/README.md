# SimTrader

Paper trading platform with virtual balances and leaderboard on ProbeChain Rydberg Testnet.

## Features

- Create accounts with virtual USD balance (100 - 1M)
- Place buy/sell trades on allowed assets
- 10% margin requirement per trade
- PnL tracking and settlement
- Win rate and leaderboard tracking
- Account reset capability
- Pre-configured assets: BTC, ETH, PRB

## Setup

```bash
npm install
cp .env.example .env
# Edit .env with your private key
npx hardhat compile
npm run deploy
```

## Contract: PaperTrading

| Function | Description |
|---|---|
| `createAccount(initialBalance)` | Create virtual account |
| `placeTrade(accountId, asset, side, amount, price)` | Place virtual trade |
| `settleTrade(tradeId, settlementPrice)` | Settle at price (settler) |
| `cancelTrade(tradeId)` | Cancel open trade |
| `getPortfolio(accountId)` | View portfolio summary |
| `getPosition(accountId, asset)` | View asset position |
| `resetAccount(accountId, newBalance)` | Start fresh |

## Network

- **Network:** ProbeChain Rydberg Testnet
- **Chain ID:** 8004
- **RPC:** https://proscan.pro/chain/rydberg-rpc
