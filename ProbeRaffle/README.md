# ProbeRaffle

On-chain raffle system with blockhash-based randomness on ProbeChain Rydberg Testnet.

## Features

- Create raffles with configurable ticket price and max tickets
- Buy tickets with PROBE
- Draw winner using blockhash randomness
- Cancel raffles with no tickets sold
- Platform fee collection

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
