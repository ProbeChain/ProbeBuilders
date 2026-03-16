# CarbonProbe - Carbon Credit Trading

ERC-20-like carbon credit token with provenance tracking on ProbeChain Rydberg Testnet.

## Contract: CarbonCredit.sol (pCARBON)

Mint credits linked to verified projects, trade them as ERC-20 tokens, and retire (burn) them with stated reasons.

### Features
- **registerProject** - Register a carbon offset project with methodology and verifier
- **mintCredits** - Mint credits linked to a specific project
- **retireCredits** - Burn credits with a retirement reason (permanent offset record)
- **ERC-20 transfers** - Standard transfer, transferFrom, approve
- **Provenance** - Every credit traceable to its originating project
- **Retirement history** - Full per-user and global retirement records

## Network
- **Chain**: ProbeChain Rydberg Testnet
- **Chain ID**: 8004
- **RPC**: https://proscan.pro/chain/rydberg-rpc

## Setup
```bash
npm install
cp .env.example .env
# Edit .env with your private key
npm run compile
npm run deploy
```
