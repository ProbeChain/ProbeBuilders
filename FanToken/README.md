# FanToken

Creator fan token platform with bonding curve pricing on ProbeChain Rydberg Testnet.

## Features

- Create fan tokens for any creator
- Bonding curve pricing: Price = supply^2 / 1,000,000
- Buy/sell tokens along the curve with automatic pricing
- Creator fee (2.5%) and platform fee (2.5%) on trades
- Reward distribution to token holders
- Proportional reward claiming

## Setup

```bash
npm install
cp .env.example .env
# Edit .env with your private key
npx hardhat compile
npm run deploy
```

## Contract: FanTokenFactory

| Function | Description |
|---|---|
| `createFanToken(creator, name, symbol, maxSupply)` | Create new fan token |
| `buyTokens(tokenId, amount)` | Buy tokens (payable) |
| `sellTokens(tokenId, amount)` | Sell tokens back to curve |
| `distributeRewards(tokenId)` | Creator deposits rewards |
| `claimRewards(tokenId)` | Claim proportional rewards |
| `getBuyPrice(tokenId, amount)` | Preview buy cost |
| `getSellPrice(tokenId, amount)` | Preview sell proceeds |

## Network

- **Network:** ProbeChain Rydberg Testnet
- **Chain ID:** 8004
- **RPC:** https://proscan.pro/chain/rydberg-rpc
