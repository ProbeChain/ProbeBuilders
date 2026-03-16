# ProbeEscrow

Three-party escrow service with dispute resolution on ProbeChain Rydberg Testnet.

## Features

- Create escrows with buyer, seller, and arbiter
- Release to seller or refund to buyer
- Dispute mechanism with arbiter resolution
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
