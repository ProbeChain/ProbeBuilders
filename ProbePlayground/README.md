# ProbePlayground

On-chain code snippet sharing and IDE registry on ProbeChain Rydberg Testnet.

## Features

- Save code snippets with title, hash, and language
- Public/private snippet visibility
- Fork existing snippets to create derivatives
- Like system for community curation
- Language-based discovery
- Popularity tracking

## Setup

```bash
npm install
cp .env.example .env
# Edit .env with your private key
npx hardhat compile
npm run deploy
```

## Contract: PlaygroundRegistry

| Function | Description |
|---|---|
| `saveSnippet(title, codeHash, language, isPublic)` | Save a new snippet |
| `forkSnippet(snippetId, newTitle, newCodeHash)` | Fork an existing snippet |
| `likeSnippet(snippetId)` | Like a public snippet |
| `getPopularSnippets(language)` | Get recent popular snippets |
| `deleteSnippet(snippetId)` | Delete own snippet |

## Network

- **Network:** ProbeChain Rydberg Testnet
- **Chain ID:** 8004
- **RPC:** https://proscan.pro/chain/rydberg-rpc
