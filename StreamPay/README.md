# StreamPay

Per-second payment streaming for continuous compensation on ProbeChain Rydberg Testnet.

## Features

- Create streams with start/stop times
- Per-second rate calculation
- Withdraw available balance at any time
- Cancel streams (splits earned/unearned)
- Track active streams per sender/recipient

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
