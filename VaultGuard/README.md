# VaultGuard

Multi-sig vault with AI-assisted anomaly detection for ProbeChain Rydberg Testnet.

## Features

- 2-of-3 multi-sig approval for withdrawals
- 1-hour withdrawal delay for security
- Emergency freeze (any signer) / unfreeze (2-of-3)
- Anomaly flagging for withdrawals exceeding 30% of vault balance
- ERC20 and native token support
- Signer replacement with 2-of-3 approval

## Contracts

| Contract | Address |
|---|---|
| GuardedVault | `TBD` |

## Quick Start

```bash
cp .env.example .env
npm install
npx hardhat compile
npx hardhat run scripts/deploy.ts --network rydberg
```

## Network

- RPC: `https://proscan.pro/chain/rydberg-rpc`
- Chain ID: `8004`
