# ProbeGlossary

On-chain terminology registry with translations on ProbeChain Rydberg Testnet.

## Features

- Add terms with definitions, categories, and languages
- Update term definitions (author or trusted editor)
- Multi-language translation support
- Category-based term search
- Contributor points system
- Trusted editor management

## Setup

```bash
npm install
cp .env.example .env
# Edit .env with your private key
npx hardhat compile
npm run deploy
```

## Contract: GlossaryRegistry

| Function | Description |
|---|---|
| `addTerm(term, definition, category, language)` | Add new term |
| `updateTerm(termId, newDefinition)` | Update definition |
| `translateTerm(termId, language, term, definition)` | Add translation |
| `searchTerms(category)` | Search by category |
| `getTranslations(termId)` | Get translations |

## Network

- **Network:** ProbeChain Rydberg Testnet
- **Chain ID:** 8004
- **RPC:** https://proscan.pro/chain/rydberg-rpc
