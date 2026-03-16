# VoiceForge

Voice model marketplace with consent verification and abuse reporting on ProbeChain Rydberg Testnet.

## Features

- **Voice Registration** — Register voice models with mandatory owner consent verification
- **Marketplace Listing** — List voices with per-use pricing
- **Pay-per-Use** — Automatic payment on each voice usage with platform fee
- **Abuse Reporting** — Community-driven abuse detection with auto-suspension threshold
- **Usage Tracking** — Complete on-chain usage logs

## Contract: VoiceMarket.sol

| Function | Description |
|---|---|
| `registerVoice(name, sampleHash, ownerConsent)` | Register a voice model |
| `listVoice(voiceId, pricePerUse)` | List voice on marketplace |
| `useVoice(voiceId)` | Use a voice (pay per use) |
| `reportAbuse(voiceId, abuseType, evidence)` | Report voice abuse |

## Setup

```bash
npm install
cp .env.example .env
# Edit .env with your private key
npx hardhat compile
npx hardhat run scripts/deploy.ts --network rydberg
```

## Network

- **Network**: ProbeChain Rydberg Testnet
- **Chain ID**: 8004
- **RPC**: https://proscan.pro/chain/rydberg-rpc
- **EVM**: London
