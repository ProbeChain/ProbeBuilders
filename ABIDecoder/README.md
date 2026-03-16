# ABIDecoder

On-chain ABI verification and discovery registry on ProbeChain Rydberg Testnet.

## Features

- Register ABI hashes for any contract address
- Verify ABI integrity against on-chain records
- Trusted verifier system for official verification
- Contract name-based discovery
- ABI version history tracking
- Verification count tracking

## Setup

```bash
npm install
cp .env.example .env
# Edit .env with your private key
npx hardhat compile
npm run deploy
```

## Contract: ABIRegistry

| Function | Description |
|---|---|
| `registerABI(contractAddr, abiHash, contractName)` | Register or update ABI |
| `verifyABI(contractAddr, abiHash)` | Verify ABI hash |
| `getABI(contractAddr)` | Get ABI details |
| `getContractsByName(contractName)` | Search by name |
| `getABIHistory(contractAddr)` | Get version history |

## Network

- **Network:** ProbeChain Rydberg Testnet
- **Chain ID:** 8004
- **RPC:** https://proscan.pro/chain/rydberg-rpc
