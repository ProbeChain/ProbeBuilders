# ProbeBuilders — Agent DApp Ecosystem

> 209+ autonomous Agent DApps built on ProbeChain Rydberg Testnet

## Overview

ProbeBuilders is the world's first on-chain Agent DApp Store. Every DApp in this repository is a real, deployable smart contract or Agent protocol running on the **ProbeChain Rydberg Testnet** (Chain ID 8004).

## Network Configuration

| Parameter | Value |
|-----------|-------|
| Network | ProbeChain Rydberg Testnet |
| Chain ID | 8004 (0x1F44) |
| Token | PROBE (18 decimals) |
| RPC | `https://proscan.pro/chain/rydberg-rpc` |
| Explorer | [proscan.pro/rydberg](https://proscan.pro/rydberg) |
| Faucet | [proscan.pro/rydberg/faucet](https://proscan.pro/rydberg/faucet) |
| Block Time | ~1 second |
| Consensus | Proof-of-Behavior (PoB) V3.0.0 |
| EVM | London-compatible |

## Quick Start

```bash
git clone https://github.com/ProbeChain/ProbeBuilders.git
cd ProbeBuilders/<DAppName>
npm install
npx hardhat compile
npx hardhat test
npx hardhat run scripts/deploy.ts --network rydberg
```

## Categories (11)

| # | Category | DApps |
|---|----------|-------|
| 1 | Agent Economy & Intent Networks | 24 |
| 2 | Compute DePIN | 12 |
| 3 | Physical DePIN | 12 |
| 4 | Data & Privacy Computing | 24 |
| 5 | ModelFi & Creator Economy | 24 |
| 6 | Agentic DeFi | 28 |
| 7 | FOCG & Autonomous Worlds | 25 |
| 8 | DeID & SocialFi | 24 |
| 9 | RWA & Enterprise | 12 |
| 10 | Developer Tools | 12 |
| 11 | Education & Growth | 12 |

## Links

- **Portal**: [probe.builders](https://probe.builders)
- **Explorer**: [proscan.pro/rydberg](https://proscan.pro/rydberg)
- **ProbeChain**: [probechain.org](https://probechain.org)

## License

MIT
