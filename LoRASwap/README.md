# LoRASwap

AI model weights exchange with ratings and custom fine-tune requests on ProbeChain Rydberg Testnet.

## Features

- **Model Listing** — List LoRA/fine-tuned model weights with license types (OpenSource, Commercial, Research, Exclusive)
- **Purchases** — Buy model weights with automatic creator payment
- **Rating System** — Rate and review purchased models (1-5 stars)
- **Custom Fine-Tuning** — Request custom fine-tunes with escrowed budget
- **Delivery & Acceptance** — Providers deliver weights, requesters accept to release payment

## Contract: ModelExchange.sol

| Function | Description |
|---|---|
| `listModel(name, weightsHash, baseModel, price, license)` | List a model for sale |
| `purchaseModel(modelId)` | Purchase a model |
| `rateModel(modelId, score, review)` | Rate a purchased model |
| `requestCustomFinetune(spec, budget)` | Request custom fine-tuning |
| `deliverFinetune(requestId, weightsHash)` | Deliver fine-tuned weights |

## Setup

```bash
npm install
cp .env.example .env
# Edit .env with your private key
npx hardhat compile
npx hardhat run scripts/deploy.ts --network rydberg
```

## Network

- **Network**: ProbeChain Rydberg Testnet
- **Chain ID**: 8004
- **RPC**: https://proscan.pro/chain/rydberg-rpc
- **EVM**: London
