# ProbeVesting

Token vesting with linear release and cliff period on ProbeChain Rydberg Testnet.

## Features

- Create vesting schedules with cliff and linear release
- Revocable schedules (returns unvested to creator)
- Release vested tokens at any time after cliff
- Track vested and releasable amounts

## Setup

```bash
npm install
cp .env.example .env
npx hardhat compile
npm run deploy
```

## Network

- **Network:** ProbeChain Rydberg Testnet
- **Chain ID:** 8004
- **RPC:** https://proscan.pro/chain/rydberg-rpc
