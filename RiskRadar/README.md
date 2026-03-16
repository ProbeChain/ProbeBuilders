# RiskRadar - DeFi Position Health Monitor

Smart contract for monitoring DeFi position health factors on ProbeChain Rydberg Testnet.

## Contract: RiskMonitor.sol

Track collateral/debt positions, receive oracle price updates, and emit liquidation alerts when health drops below threshold.

### Features
- **registerPosition** - Register a DeFi position with collateral and debt details
- **updatePrice** - Oracle-only price feed updates
- **checkHealth** - Calculate health factor for any position
- **evaluatePosition** - Check health and emit LiquidateAlert if below 1.2x
- **Batch operations** - Batch price updates and health checks
- **Custom thresholds** - Per-position alert thresholds

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
