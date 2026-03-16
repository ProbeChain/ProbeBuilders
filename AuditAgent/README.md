# AuditAgent - Smart Contract Audit Registry

Decentralized audit marketplace with auditor reputation, severity-based rewards, and dispute resolution on ProbeChain Rydberg Testnet.

## Features
- Request audits with bounty rewards
- Auditors stake PROBE and submit reports
- Severity levels: Critical, High, Medium, Low, Info
- Reputation system with severity-based bonuses
- Dispute resolution mechanism
- Approve/reject workflow

## Deploy
```bash
npm install
cp .env.example .env  # add your private key
npx hardhat compile
npm run deploy
```

## Network
- **Chain**: ProbeChain Rydberg Testnet
- **Chain ID**: 8004
- **RPC**: https://proscan.pro/chain/rydberg-rpc
