# ProbeNewsletter

Decentralized newsletter subscription platform on ProbeChain Rydberg Testnet.

## Features

- Create newsletters with configurable frequency and price
- Paid subscriptions with 30-day duration
- Publish editions with IPFS content hashes
- Unsubscribe anytime
- Publisher revenue claim
- Platform fee collection
- Subscription status tracking

## Setup

```bash
npm install
cp .env.example .env
# Edit .env with your private key
npx hardhat compile
npm run deploy
```

## Contract: NewsletterDAO

| Function | Description |
|---|---|
| `createNewsletter(name, frequency, price)` | Create newsletter |
| `subscribe(newsletterId)` | Subscribe (payable) |
| `publishEdition(newsletterId, contentHash)` | Publish edition |
| `unsubscribe(newsletterId)` | Unsubscribe |
| `claimPublisherRewards()` | Claim revenue |

## Network

- **Network:** ProbeChain Rydberg Testnet
- **Chain ID:** 8004
- **RPC:** https://proscan.pro/chain/rydberg-rpc
