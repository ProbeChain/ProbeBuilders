# ProbeSDK

SDK registry with download integrity verification on ProbeChain Rydberg Testnet.

## Features

- Register SDKs with name, language, version, and download hash
- Multi-language support: TypeScript, Python, Rust, Go
- Publish new versions with hash verification
- Verify download integrity against on-chain records
- Deprecate outdated versions
- Verified publisher system

## Setup

```bash
npm install
cp .env.example .env
# Edit .env with your private key
npx hardhat compile
npm run deploy
```

## Contract: SDKRegistry

| Function | Description |
|---|---|
| `registerSDK(name, language, version, downloadHash)` | Register a new SDK |
| `updateSDK(sdkId, version, downloadHash)` | Publish a new version |
| `verifyDownload(sdkId, hash)` | Verify download hash on-chain |
| `getLatestVersion(name, language)` | Get latest non-deprecated version |
| `deprecateVersion(sdkId, versionIndex)` | Deprecate a version |
| `setVerifiedPublisher(publisher, status)` | Verify/unverify publisher (owner) |

## Network

- **Network:** ProbeChain Rydberg Testnet
- **Chain ID:** 8004
- **RPC:** https://proscan.pro/chain/rydberg-rpc
