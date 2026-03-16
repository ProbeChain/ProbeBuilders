# ProbeWrapped

WETH-pattern wrapper for native PROBE token (wPROBE) on ProbeChain Rydberg Testnet.

## Features

- Wrap native PROBE to ERC-20 wPROBE
- Unwrap wPROBE back to native PROBE
- Auto-wrap on direct PROBE send (receive function)
- Full ERC-20 compatibility (transfer, approve, transferFrom)
- Reserve backing verification

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
