# ReferralProbe

Multi-tier referral tracking and reward system on ProbeChain Rydberg Testnet.

## Features

- Register referrer with unique code
- Two-tier referral rewards (direct + indirect)
- Claim accumulated rewards
- Configurable reward tier amounts
- Referral chain traversal (up to 5 levels)
- Direct referral listing

## Setup

```bash
npm install
cp .env.example .env
# Edit .env with your private key
npx hardhat compile
npm run deploy
```

## Contract: ReferralSystem

| Function | Description |
|---|---|
| `registerReferrer(code)` | Register with referral code |
| `useReferralCode(code)` | Use a referral code |
| `claimReferralReward()` | Claim pending rewards |
| `setRewardTiers(tier1, tier2)` | Set tier amounts (owner) |
| `getReferralChain(user)` | Get referral chain |

## Network

- **Network:** ProbeChain Rydberg Testnet
- **Chain ID:** 8004
- **RPC:** https://proscan.pro/chain/rydberg-rpc
