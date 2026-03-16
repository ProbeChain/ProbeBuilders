# TipBot

Social tipping protocol with native and ERC-20 token support on ProbeChain Rydberg Testnet.

## Features

- Send native currency tips with optional messages
- Send ERC-20 token tips (whitelisted tokens)
- Platform fee system (configurable, max 10%)
- Pull-based withdrawal pattern for security
- Leaderboard tracking via events
- Pausable for emergency

## Setup

```bash
npm install
cp .env.example .env
# Edit .env with your private key
npx hardhat compile
npm run deploy
```

## Contract: TipJar

| Function | Description |
|---|---|
| `tip(recipient, message)` | Send native tip (payable) |
| `tipWithToken(recipient, token, amount, message)` | Send ERC-20 tip |
| `withdrawTips()` | Withdraw accumulated native tips |
| `withdrawTokenTips(token)` | Withdraw accumulated token tips |
| `setMinTip(newMinTip)` | Set minimum tip (owner) |
| `setAllowedToken(token, allowed)` | Whitelist tokens (owner) |

## Network

- **Network:** ProbeChain Rydberg Testnet
- **Chain ID:** 8004
- **RPC:** https://proscan.pro/chain/rydberg-rpc
