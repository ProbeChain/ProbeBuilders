# ProbeReport

Research report NFTs with citations and impact on ProbeChain Rydberg Testnet (Chain ID: 8004).

## Contract: ResearchNFT.sol (ERC-721)

Publish research as NFTs, sell access, build citation graphs, track research impact.

### Key Functions
- `publishReport(title, abstractHash, fullReportHash, price)` -- Publish a report NFT
- `purchaseReport(reportId)` payable -- Purchase access to a report
- `citeReport(citingReportId, citedReportId)` -- Record a citation
- `getResearchImpact(reportId)` -- Get impact score

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
