# ProbeCLI

CLI tool registry on-chain for download integrity verification on ProbeChain Rydberg Testnet.

## Features

- Register tools with version, hash, and platform info
- Publish new versions with download hash verification
- Look up tools by name
- Verify download integrity against on-chain hashes
- Deprecate old versions
- Verified publisher system

## Setup

```bash
npm install
cp .env.example .env
# Edit .env with your private key
npx hardhat compile
npm run deploy
```

## Contract: ToolRegistry

| Function | Description |
|---|---|
| `registerTool(name, desc, repo, version, hash, platform, url)` | Register new tool |
| `updateTool(toolId, version, hash, platform, url)` | Publish new version |
| `getLatestVersion(toolId)` | Get latest non-deprecated version |
| `verifyDownload(toolId, hash)` | Verify download hash |
| `deprecateVersion(toolId, versionIndex)` | Deprecate a version |
| `getToolIdByName(name)` | Look up tool by name |

## Network

- **Network:** ProbeChain Rydberg Testnet
- **Chain ID:** 8004
- **RPC:** https://proscan.pro/chain/rydberg-rpc
