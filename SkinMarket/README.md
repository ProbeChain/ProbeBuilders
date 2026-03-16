# SkinMarket - Cross-Game Item Marketplace

NFT marketplace supporting both ERC-721 and ERC-1155 items with listings, offers, and negotiation on ProbeChain Rydberg Testnet.

## Features

- **Multi-Standard Support**: Trade both ERC-721 and ERC-1155 NFTs
- **Direct Listings**: List items at fixed prices for instant purchase
- **Offer System**: Make time-limited offers on any listing; sellers can accept or let expire
- **Game Tags**: Items tagged with gameId for cross-game discovery
- **Platform Fees**: Configurable fee (default 2.5%) on sales

## Contract: ItemMarket.sol

| Function | Description |
|----------|-------------|
| `listItem(...)` | List an NFT for sale |
| `buyItem(listingId)` | Buy at listed price |
| `makeOffer(listingId, hours)` | Make a time-limited offer |
| `acceptOffer(offerId)` | Accept an offer (seller) |
| `cancelListing(listingId)` | Cancel your listing |

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
