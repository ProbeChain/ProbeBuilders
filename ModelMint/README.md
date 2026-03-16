# ModelMint - AI Model Tokenization

ERC-721 NFTs representing AI model ownership with ERC-2981 royalty enforcement and model versioning on ProbeChain Rydberg Testnet.

## Features
- Mint AI models as NFTs with unique model hash
- ERC-2981 royalty info for secondary sale enforcement
- Model versioning with changelog
- Creator-controlled royalty percentage (up to 25%)
- Transfer with automatic royalty payment

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
