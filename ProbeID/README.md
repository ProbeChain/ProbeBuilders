# ProbeID

Universal identity system on ProbeChain Rydberg Testnet supporting Human, Agent, and Organization identity types with verifiable attributes.

## Features

- Create identities with public key association
- Add attributes with proof hashes (e.g., email, name, KYC)
- Verifier-based attribute verification
- Attribute revocation by owner or verifier
- Identity deactivation

## Setup

```bash
npm install
cp .env.example .env
# Add your private key to .env
npx hardhat compile
npm run deploy
```

## Network

- **Network:** ProbeChain Rydberg Testnet
- **Chain ID:** 8004
- **RPC:** https://proscan.pro/chain/rydberg-rpc
