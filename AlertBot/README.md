# AlertBot - On-Chain Alert Subscription

Pay-per-alert subscription system with watcher rewards on ProbeChain Rydberg Testnet.

## Features

- **Alert Creation**: Define alerts with event types (PriceAbove, LargeTransfer, etc.), thresholds, and pricing
- **Subscriptions**: Subscribe to alerts with prepaid balance; auto-deactivate when depleted
- **Watcher System**: Authorized watchers trigger alerts and earn fees
- **Callback Support**: Optional contract callbacks when alerts trigger
- **Pay-per-Alert**: Subscribers charged per trigger; creators earn revenue

## Contract: AlertSubscription.sol

| Function | Description |
|----------|-------------|
| `createAlert(type, threshold, callback, desc, price)` | Create alert definition |
| `subscribe(alertId)` | Subscribe with prepaid balance |
| `triggerAlert(alertId, data)` | Trigger alert (watcher) |
| `chargeSubscriber(alertId, subscriber)` | Charge subscriber (watcher) |
| `cancelSubscription(subId)` | Cancel and refund balance |

## Quick Start

```bash
cp .env.example .env
npm install
npx hardhat compile
npx hardhat run scripts/deploy.ts --network rydberg
```

## Network

- **Network**: ProbeChain Rydberg Testnet
- **Chain ID**: 8004
- **RPC**: https://proscan.pro/chain/rydberg-rpc
