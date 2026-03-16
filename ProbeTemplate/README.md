# ProbeTemplate

Dapp template marketplace on ProbeChain Rydberg Testnet.

## Features

- Publish templates with categories: DeFi, NFT, DAO, GameFi
- Free and paid templates with escrow payments
- Use/purchase templates with platform fee
- Rating system (1-5 stars)
- Featured templates curation
- Publisher revenue withdrawal
- Category-based discovery

## Setup

```bash
npm install
cp .env.example .env
# Edit .env with your private key
npx hardhat compile
npm run deploy
```

## Contract: TemplateStore

| Function | Description |
|---|---|
| `publishTemplate(name, category, bytecodeHash, docsHash, price)` | Publish template |
| `useTemplate(templateId)` | Use/purchase template (payable) |
| `rateTemplate(templateId, score)` | Rate 1-5 stars |
| `getFeaturedTemplates()` | Get featured templates |
| `withdrawRevenue()` | Publisher withdraws earnings |

## Network

- **Network:** ProbeChain Rydberg Testnet
- **Chain ID:** 8004
- **RPC:** https://proscan.pro/chain/rydberg-rpc
