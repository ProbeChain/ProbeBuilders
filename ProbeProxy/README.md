# ProbeProxy

Transparent upgradeable proxy pattern on ProbeChain Rydberg Testnet.

## Features

- EIP-1967 compliant storage slots
- Transparent proxy pattern (admin vs user call routing)
- Two-step admin transfer (propose + accept)
- Upgrade with optional initialization call
- Contract verification for implementation addresses
- Delegatecall forwarding for all non-admin calls

## Setup

```bash
npm install
cp .env.example .env
# Edit .env with your private key
npx hardhat compile
npm run deploy
```

## Contract: UpgradeableProxy

| Function | Description |
|---|---|
| `upgradeTo(newImplementation)` | Upgrade implementation (admin) |
| `upgradeToAndCall(newImpl, data)` | Upgrade and initialize (admin) |
| `getImplementation()` | Get current implementation (admin) |
| `changeAdmin(newAdmin)` | Propose new admin (admin) |
| `acceptAdmin()` | Accept admin role (pending admin) |

## Deployment

1. Deploy your implementation contract first
2. Deploy UpgradeableProxy with (implAddress, adminAddress, initData)
3. Interact with proxy address using implementation's ABI

## Network

- **Network:** ProbeChain Rydberg Testnet
- **Chain ID:** 8004
- **RPC:** https://proscan.pro/chain/rydberg-rpc
