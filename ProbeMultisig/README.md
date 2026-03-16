# ProbeMultisig

Multi-signature wallet with configurable confirmation threshold on ProbeChain Rydberg Testnet.

## Features

- Submit, confirm, and execute transactions
- Configurable required confirmations
- Revoke confirmations
- Owner management via multisig
- Auto-confirm on submission

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
