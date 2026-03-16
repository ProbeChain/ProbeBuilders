# ProbeRent

NFT rental marketplace with collateral on ProbeChain Rydberg Testnet (Chain ID: 8004).

## Contract: NFTRental.sol

List NFTs for rent, rent with collateral, return or handle late returns.

### Key Functions
- `listForRent(nftContract, tokenId, dailyRate, maxDuration)` -- List NFT for rent
- `rent(listingId, days)` payable -- Rent an NFT
- `returnNFT(rentalId)` -- Return rented NFT
- `claimLateReturn(rentalId)` -- Lender claims collateral for default

### Deploy
```bash
cp .env.example .env
npm install
npx hardhat compile
npx hardhat run scripts/deploy.ts --network rydberg
```

## Network
- **Chain ID:** 8004
- **EVM:** London
- **Solidity:** 0.8.24
