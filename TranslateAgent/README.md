# TranslateAgent

Translation bounty system with community quality voting on ProbeChain Rydberg Testnet.

## Features

- Create translation bounties with ETH rewards
- Submit translations with IPFS proof links
- Community quality voting on submissions
- Dispute resolution with staking
- Translator reputation tracking
- Deadline enforcement

## Setup

```bash
npm install
cp .env.example .env
# Edit .env with your private key
npx hardhat compile
npm run deploy
```

## Contract: TranslationBounty

| Function | Description |
|---|---|
| `createBounty(sourceTextHash, sourceLang, targetLang, deadline)` | Create bounty (payable) |
| `submitTranslation(bountyId, translatedHash, proofURI)` | Submit translation |
| `approveTranslation(bountyId, submissionIndex)` | Approve and pay |
| `disputeTranslation(bountyId)` | Dispute with stake |
| `voteQuality(bountyId, submissionIndex, positive)` | Community vote |
| `cancelBounty(bountyId)` | Cancel if no submissions |

## Network

- **Network:** ProbeChain Rydberg Testnet
- **Chain ID:** 8004
- **RPC:** https://proscan.pro/chain/rydberg-rpc
