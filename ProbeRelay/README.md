# ProbeRelay

Meta-transaction relay for gasless experience on ProbeChain Rydberg Testnet.

## Features

- Relayer registration with staking
- EIP-712 typed data signature verification
- Gasless meta-transaction execution
- Relayer earnings from relay fees
- Nonce-based replay protection
- Relay record tracking
- Configurable relay fees and minimum stake

## Setup

```bash
npm install
cp .env.example .env
# Edit .env with your private key
npx hardhat compile
npm run deploy
```

## Contract: GaslessRelay

| Function | Description |
|---|---|
| `registerRelayer()` | Register with stake (payable) |
| `relay(from, to, value, gas, data, signature)` | Relay meta-tx |
| `withdrawRelayerEarnings()` | Withdraw earnings |
| `withdrawStake()` | Withdraw stake (deactivates) |
| `getNonce(user)` | Get user nonce |

## Network

- **Network:** ProbeChain Rydberg Testnet
- **Chain ID:** 8004
- **RPC:** https://proscan.pro/chain/rydberg-rpc
