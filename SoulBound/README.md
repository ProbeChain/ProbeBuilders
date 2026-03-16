# SoulBound

Non-transferable soulbound tokens for achievements, credentials, and memberships on ProbeChain Rydberg Testnet.

## Features

- Issue soulbound tokens (Achievement, Credential, Membership)
- Non-transferable (transfer/approve always revert)
- Revokable by issuer or owner
- Metadata URI support
- Authorized issuer management

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
