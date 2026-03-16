# RoyaltyAgent - NFT Royalty Enforcer

On-chain NFT royalty tracking and enforcement system on ProbeChain Rydberg Testnet.

## Features

- **Collection Registration**: Register NFT collections with royalty percentage and recipient
- **Sale Recording**: Authorized recorders log secondary sales with automatic royalty calculation
- **Instant Royalties**: Royalties can be paid at sale time via msg.value
- **Deferred Claims**: Creators can claim accumulated unpaid royalties
- **Analytics**: Track total volume, royalty accrued/claimed, and sale count per collection

## Contract: RoyaltyEnforcer.sol

| Function | Description |
|----------|-------------|
| `registerCollection(nft, bps, recipient)` | Register collection royalties |
| `recordSale(nft, tokenId, seller, buyer, price)` | Record a secondary sale |
| `claimRoyalties(nftContract)` | Claim unpaid royalties |
| `getRoyaltyInfo(nftContract)` | Get collection royalty stats |
| `calculateRoyalty(nft, price)` | Calculate royalty for a price |

## Quick Start

```bash
cp .env.example .env
npm install
npx hardhat compile
npx hardhat run scripts/deploy.ts --network rydberg
```

## Network

- **Network**: ProbeChain Rydberg Testnet
- **Chain ID**: 8004
- **RPC**: https://proscan.pro/chain/rydberg-rpc
