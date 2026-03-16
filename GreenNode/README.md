# GreenNode — Green Energy Verification

Green energy verification and credit system on ProbeChain Rydberg Testnet (Chain ID 8004).

## Features

- Register renewable energy sources with certificates
- Auditor verification of energy certificates
- Mint green credits based on verified generation
- Transferable and redeemable credits

## Contract: GreenEnergy.sol

| Function | Description |
|---|---|
| `registerSource` | Register a green energy source |
| `verifyCertificate` | Auditor verifies source certificate |
| `mintGreenCredits` | Mint credits for generation |
| `redeemCredits` | Redeem green credits |
| `transferCredits` | Transfer credits to another address |

## Quick Start

```bash
cp .env.example .env
npm install
npx hardhat compile
npx hardhat run scripts/deploy.ts --network rydberg
```

## Network

- **Network:** ProbeChain Rydberg Testnet
- **Chain ID:** 8004
- **RPC:** https://proscan.pro/chain/rydberg-rpc
