# ProbeOTC - Over-the-Counter Trading Desk

Smart contract for escrow-based OTC trades on ProbeChain Rydberg Testnet.

## Contract: OTCDesk.sol

Large trades with escrow, partial fills, and privacy (no public orderbook, only events).

### Features
- **createOrder** - Create a sell order with tokens escrowed in the contract
- **fillOrder** - Buy tokens from an order (partial or full fills)
- **cancelOrder** - Cancel and reclaim unsold tokens
- **Protocol fees** - Configurable fee in basis points (default 0.3%)
- **Privacy-preserving** - No public orderbook view; discovery via events only

## Network
- **Chain**: ProbeChain Rydberg Testnet
- **Chain ID**: 8004
- **RPC**: https://proscan.pro/chain/rydberg-rpc

## Setup
```bash
npm install
cp .env.example .env
# Edit .env with your private key
npm run compile
npm run deploy
```
