# TicketProbe

Event ticket NFTs with anti-scalping on ProbeChain Rydberg Testnet (Chain ID: 8004).

## Contract: TicketNFT.sol (ERC-721)

Create events, mint tickets, validate at venue, transfer with anti-scalp price cap (max 1.5x).

### Key Functions
- `createEvent(name, date, venue, maxTickets, price)` -- Create an event
- `mintTicket(eventId)` payable -- Buy a ticket
- `validateTicket(ticketId)` -- Scanner validates at venue
- `transferTicket(to, ticketId, resalePrice)` -- Transfer with anti-scalp

### Deploy
```bash
cp .env.example .env
npm install
npx hardhat compile
npx hardhat run scripts/deploy.ts --network rydberg
```

## Network
- **Chain ID:** 8004
- **EVM:** London
- **Solidity:** 0.8.24
