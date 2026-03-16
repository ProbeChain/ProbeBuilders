# ProbePay

Payment gateway with merchant registration and multi-token support for ProbeChain Rydberg Testnet.

## Features

- Merchant registration and management
- ERC20 and native currency payments
- Payment escrow with confirm/refund/expire lifecycle
- Configurable platform fee (default 1%)
- Payment dispute mechanism
- 24-hour auto-expiry for unclaimed payments

## Contracts

| Contract | Address |
|---|---|
| PaymentGateway | `TBD` |

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
