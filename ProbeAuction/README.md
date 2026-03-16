# ProbeAuction

English auction house for NFTs with minimum bid increments on ProbeChain Rydberg Testnet.

## Features

- Create auctions with start price and duration
- Minimum bid increment enforcement (5%)
- Auto-extend on late bids (last 10 minutes)
- Outbid fund withdrawal
- Platform fee on settlements

## Setup

```bash
npm install
cp .env.example .env
npx hardhat compile
npm run deploy
```

## Network

- **Network:** ProbeChain Rydberg Testnet
- **Chain ID:** 8004
- **RPC:** https://proscan.pro/chain/rydberg-rpc
