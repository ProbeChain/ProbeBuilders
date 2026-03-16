# FaucetPlus

Smart faucet with anti-sybil protection and tiered claims on ProbeChain Rydberg Testnet.

## Features

- Per-address cooldown enforcement
- Three tiers: Standard, Verified (2x), Premium (5x)
- Daily global distribution limit
- Address banning for abuse prevention
- Batch whitelisting
- Auto-funding via receive()

## Setup

```bash
npm install
cp .env.example .env
# Edit .env with your private key
npx hardhat compile
npm run deploy
```

## Contract: SmartFaucet

| Function | Description |
|---|---|
| `claimTokens()` | Claim faucet tokens |
| `setClaimAmount(newAmount)` | Set base claim (owner) |
| `setCooldownPeriod(newCooldown)` | Set cooldown (owner) |
| `addToWhitelist(addr, tier)` | Set address tier (owner) |
| `banAddress(addr, isBanned)` | Ban/unban address (owner) |
| `timeUntilNextClaim(addr)` | Check cooldown remaining |

## Network

- **Network:** ProbeChain Rydberg Testnet
- **Chain ID:** 8004
- **RPC:** https://proscan.pro/chain/rydberg-rpc
