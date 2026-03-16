# ProbeWorld

Virtual land registry with 2D coordinate grid, building system, and ERC-721 plots on ProbeChain Rydberg Testnet.

## Features

- Mint plots on a 2D coordinate grid (variable size 1x1 to 10x10)
- Collision detection prevents overlapping claims
- Build on owned plots with multiple building types
- Query neighbors in 4 directions
- ERC-721 compliant for trading on any NFT marketplace

## Contract: LandRegistry.sol

| Function | Description |
|----------|-------------|
| `mintPlot(x, y, size)` | Mint a new land plot (payable) |
| `transferPlot(to, plotId)` | Transfer plot ownership |
| `buildOnPlot(plotId, buildingType, dataHash)` | Place a building on your plot |
| `getPlotInfo(plotId)` | Get full plot details |
| `getNeighbors(plotId)` | Get neighboring plot IDs |

## Deployment

```bash
cp .env.example .env
npm install
npx hardhat compile
npx hardhat run scripts/deploy.ts --network rydberg
```

## Network

- **Network:** ProbeChain Rydberg Testnet
- **Chain ID:** 8004
- **RPC:** https://proscan.pro/chain/rydberg-rpc
- **EVM:** London
