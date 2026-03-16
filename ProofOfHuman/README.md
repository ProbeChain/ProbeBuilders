# ProofOfHuman

Sybil resistance via challenge-response human verification on ProbeChain Rydberg Testnet. Supports captcha, social, and biometric challenge types.

## Features

- Challenge-response verification system
- Multiple challenge types (Captcha, Social, Biometric)
- Expirable verification records
- Authorized verifier management

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
