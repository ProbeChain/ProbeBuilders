# LandAgent

Virtual real estate AI valuation, appraisal, and marketplace on ProbeChain Rydberg Testnet.

## Features

- Register virtual land from any NFT contract
- Approved appraiser system with methodology tracking
- Average valuation calculation across multiple appraisals
- List land for sale with asking price
- Bid system with accept/withdraw functionality
- Platform fee on successful sales

## Contract: LandValuation.sol

| Function | Description |
|----------|-------------|
| `registerLand(landContract, tokenId, metadataHash)` | Register a land asset |
| `submitAppraisal(landId, value, methodology)` | Appraiser submits valuation |
| `getValuation(landId)` | Get average valuation |
| `listForSale(landId, askPrice)` | List land for sale |
| `makeBid(landId)` | Place a bid (payable) |
| `acceptBid(bidId)` | Accept a bid |

## Deployment

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
- **EVM:** London
