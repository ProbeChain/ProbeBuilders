# ProbeInsight

Enterprise analytics registry for ProbeChain Rydberg Testnet (Chain ID 8004).

## Contract: InsightRegistry

- **publishReport(title, dataHash, category, price)** — Publish an analytics report.
- **purchaseReport(reportId)** — Purchase access with revenue sharing to author.
- **rateReport(reportId, rating)** — Rate a purchased report (1-5 stars).
- **getTopReports(limit)** — Retrieve top report IDs.
- Author reputation tracking, platform fee system.

## Setup

```bash
npm install
cp .env.example .env
# Add your private key to .env
npx hardhat compile
npx hardhat run scripts/deploy.ts --network rydberg
```
