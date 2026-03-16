# FragmentNFT - NFT Fractionalization

Lock ERC-721 NFTs and issue fractional ERC-20 shares with a buyout mechanism on ProbeChain Rydberg Testnet.

## Features
- Fractionalize any ERC-721 into divisible shares
- Buy and transfer shares with allowance system
- Automatic buyout trigger at >80% ownership
- Redeem underlying NFT when holding 100% of shares
- Platform fee on share purchases

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
