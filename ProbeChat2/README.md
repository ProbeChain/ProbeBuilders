# ProbeChat2

Group messaging for ProbeChain Rydberg Testnet (Chain ID: 8004).

## Contract: GroupChat.sol

On-chain group chat with admin controls, member management, and message events.

### Key Functions
- `createGroup(name, members[])` — Create a chat group
- `sendMessage(groupId, contentHash)` — Send a message
- `addMember(groupId, member)` — Add a member (admin)
- `removeMember(groupId, member)` — Remove a member (admin)

## Setup
```bash
npm install
cp .env.example .env
npx hardhat compile
npm run deploy
```

## Network
- **Chain ID:** 8004
- **EVM:** London
- **Solidity:** 0.8.24
