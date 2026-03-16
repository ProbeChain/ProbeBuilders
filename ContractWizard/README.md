# ContractWizard - Contract Template Registry

On-chain contract template marketplace with CREATE2 factory deployment, versioning, and community ratings on ProbeChain Rydberg Testnet.

## Features
- Register reusable contract templates with bytecode verification
- One-click CREATE2 deployment from templates
- Predictable deployment addresses
- Template versioning with changelogs
- Community rating system (1-5 stars, must deploy first)
- Category-based browsing (Token, NFT, DeFi, GameFi, DAO, Utility)
- Author revenue from deploy fees

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
