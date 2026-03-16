# ProbeAsset - Real World Asset Tokenization

ERC-20 token with KYC whitelist-gated transfers, asset valuation tracking, and compliance enforcement on ProbeChain Rydberg Testnet.

## Features
- Tokenize real world assets (real estate, commodities, bonds, equity, art)
- KYC whitelist-gated transfers for compliance
- Compliance officer role for managing whitelists
- Asset valuation updates with timestamp tracking
- Balance freezing for regulatory compliance
- Batch KYC approval
- Asset redemption (token burning)

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
