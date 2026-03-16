// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title CardGame
 * @author ProbeBuilders
 * @notice Trading card game with pack minting, deck building, and wagered matches
 * @dev Deployed on ProbeChain Rydberg Testnet (Chain ID 8004)
 */
contract CardGame {
    // ─── Ownership ───────────────────────────────────────────────────
    address public owner;
    modifier onlyOwner() { require(msg.sender == owner, "CardGame: not owner"); _; }
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "CardGame: zero address");
        owner = newOwner;
    }

    // ─── Pausable ────────────────────────────────────────────────────
    bool public paused;
    modifier whenNotPaused() { require(!paused, "CardGame: paused"); _; }
    function pause() external onlyOwner { paused = true; }
    function unpause() external onlyOwner { paused = false; }

    // ─── Reentrancy Guard ────────────────────────────────────────────
    uint256 private _status = 1;
    modifier nonReentrant() { require(_status != 2, "CardGame: reentrant"); _status = 2; _; _status = 1; }

    // ─── Enums & Structs ─────────────────────────────────────────────
    enum Element { Fire, Water, Earth, Wind, Dark, Light }
    enum Rarity { Common, Uncommon, Rare, Epic, Legendary }
    enum MatchStatus { Pending, Resolved, Cancelled }

    /// @notice Represents a single card
    struct Card {
        uint256 attack;
        uint256 defense;
        Element element;
        Rarity rarity;
        uint256 mintedAt;
    }

    /// @notice Represents a player's deck of 5 cards
    struct Deck {
        uint256[5] cardIds;
        address player;
        uint256 totalPower;
        bool active;
    }

    /// @notice Represents a wagered match
    struct Match {
        uint256 challengerDeckId;
        uint256 opponentDeckId;
        address challenger;
        address opponent;
        uint256 wager;
        MatchStatus status;
        address winner;
        uint256 createdAt;
    }

    // ─── State ───────────────────────────────────────────────────────
    uint256 public nextCardId = 1;
    uint256 public nextDeckId = 1;
    uint256 public nextMatchId = 1;

    uint256 public basicPackPrice = 0.001 ether;
    uint256 public premiumPackPrice = 0.005 ether;
    uint256 public constant CARDS_PER_PACK = 5;
    uint256 public constant DECK_SIZE = 5;

    mapping(uint256 => Card) public cards;
    mapping(address => uint256[]) public playerCards;
    mapping(uint256 => address) public cardOwner;
    mapping(uint256 => Deck) public decks;
    mapping(uint256 => Match) public matches;
    mapping(address => uint256) public playerWins;
    mapping(address => uint256) public playerLosses;

    // ─── Events ──────────────────────────────────────────────────────
    event PackMinted(address indexed player, uint256 packType, uint256[] cardIds);
    event DeckCreated(uint256 indexed deckId, address indexed player, uint256 totalPower);
    event MatchCreated(uint256 indexed matchId, address indexed challenger, address indexed opponent, uint256 wager);
    event MatchResolved(uint256 indexed matchId, address indexed winner, uint256 prize);
    event MatchCancelled(uint256 indexed matchId);

    // ─── Constructor ─────────────────────────────────────────────────
    constructor() {
        owner = msg.sender;
    }

    // ─── Pack Minting ────────────────────────────────────────────────

    /// @notice Mint a card pack (0 = basic, 1 = premium)
    /// @param packType 0 for basic, 1 for premium (higher rarity chance)
    function mintPack(uint256 packType) external payable whenNotPaused {
        require(packType <= 1, "CardGame: invalid pack type");
        uint256 price = packType == 0 ? basicPackPrice : premiumPackPrice;
        require(msg.value >= price, "CardGame: insufficient payment");

        uint256[] memory newCards = new uint256[](CARDS_PER_PACK);
        for (uint256 i = 0; i < CARDS_PER_PACK; i++) {
            uint256 cardId = nextCardId++;
            uint256 seed = uint256(keccak256(abi.encodePacked(
                block.timestamp, block.prevrandao, msg.sender, cardId, i
            )));

            Rarity rarity = _determineRarity(seed, packType);
            (uint256 atk, uint256 def) = _generateStats(seed, rarity);
            Element element = Element(seed % 6);

            cards[cardId] = Card({
                attack: atk,
                defense: def,
                element: element,
                rarity: rarity,
                mintedAt: block.timestamp
            });
            cardOwner[cardId] = msg.sender;
            playerCards[msg.sender].push(cardId);
            newCards[i] = cardId;
        }

        emit PackMinted(msg.sender, packType, newCards);
    }

    /// @notice Create a deck from 5 cards you own
    /// @param cardIds Array of exactly 5 card IDs
    function createDeck(uint256[5] calldata cardIds) external whenNotPaused {
        uint256 totalPower = 0;
        for (uint256 i = 0; i < DECK_SIZE; i++) {
            require(cardOwner[cardIds[i]] == msg.sender, "CardGame: not card owner");
            // Check no duplicates
            for (uint256 j = i + 1; j < DECK_SIZE; j++) {
                require(cardIds[i] != cardIds[j], "CardGame: duplicate card");
            }
            totalPower += cards[cardIds[i]].attack + cards[cardIds[i]].defense;
        }

        uint256 deckId = nextDeckId++;
        decks[deckId] = Deck({
            cardIds: cardIds,
            player: msg.sender,
            totalPower: totalPower,
            active: true
        });

        emit DeckCreated(deckId, msg.sender, totalPower);
    }

    /// @notice Challenge another player's deck with a wager
    /// @param deckId Your deck ID
    /// @param opponentDeckId Opponent's deck ID
    function challengePlayer(uint256 deckId, uint256 opponentDeckId) external payable whenNotPaused {
        require(msg.value > 0, "CardGame: wager required");
        Deck storage myDeck = decks[deckId];
        Deck storage oppDeck = decks[opponentDeckId];
        require(myDeck.player == msg.sender, "CardGame: not your deck");
        require(myDeck.active, "CardGame: your deck inactive");
        require(oppDeck.active, "CardGame: opponent deck inactive");
        require(oppDeck.player != msg.sender, "CardGame: cannot challenge self");

        uint256 matchId = nextMatchId++;
        matches[matchId] = Match({
            challengerDeckId: deckId,
            opponentDeckId: opponentDeckId,
            challenger: msg.sender,
            opponent: oppDeck.player,
            wager: msg.value,
            status: MatchStatus.Pending,
            winner: address(0),
            createdAt: block.timestamp
        });

        emit MatchCreated(matchId, msg.sender, oppDeck.player, msg.value);
    }

    /// @notice Resolve a match (owner acts as referee using on-chain data)
    /// @param matchId The match to resolve
    /// @param winnerId 0 = challenger wins, 1 = opponent wins
    function resolveMatch(uint256 matchId, uint256 winnerId) external onlyOwner nonReentrant {
        Match storage m = matches[matchId];
        require(m.status == MatchStatus.Pending, "CardGame: match not pending");
        require(winnerId <= 1, "CardGame: invalid winner");

        m.status = MatchStatus.Resolved;
        address winnerAddr = winnerId == 0 ? m.challenger : m.opponent;
        m.winner = winnerAddr;

        uint256 prize = m.wager;
        if (winnerId == 0) {
            playerWins[m.challenger]++;
            playerLosses[m.opponent]++;
        } else {
            playerWins[m.opponent]++;
            playerLosses[m.challenger]++;
        }

        // Transfer wager to winner (2% fee to contract)
        uint256 fee = prize * 2 / 100;
        uint256 payout = prize - fee;

        (bool success, ) = payable(winnerAddr).call{value: payout}("");
        require(success, "CardGame: payout failed");

        emit MatchResolved(matchId, winnerAddr, payout);
    }

    /// @notice Cancel a pending match (challenger can cancel before resolution)
    function cancelMatch(uint256 matchId) external nonReentrant {
        Match storage m = matches[matchId];
        require(m.status == MatchStatus.Pending, "CardGame: match not pending");
        require(m.challenger == msg.sender, "CardGame: not challenger");
        require(block.timestamp > m.createdAt + 1 hours, "CardGame: too early to cancel");

        m.status = MatchStatus.Cancelled;

        (bool success, ) = payable(m.challenger).call{value: m.wager}("");
        require(success, "CardGame: refund failed");

        emit MatchCancelled(matchId);
    }

    // ─── Internal ────────────────────────────────────────────────────

    function _determineRarity(uint256 seed, uint256 packType) internal pure returns (Rarity) {
        uint256 roll = (seed >> 8) % 100;
        if (packType == 1) roll = roll > 20 ? roll - 20 : 0; // premium bias
        if (roll < 2) return Rarity.Legendary;
        if (roll < 8) return Rarity.Epic;
        if (roll < 22) return Rarity.Rare;
        if (roll < 50) return Rarity.Uncommon;
        return Rarity.Common;
    }

    function _generateStats(uint256 seed, Rarity rarity) internal pure returns (uint256 atk, uint256 def) {
        uint256 base;
        if (rarity == Rarity.Common) base = 10;
        else if (rarity == Rarity.Uncommon) base = 20;
        else if (rarity == Rarity.Rare) base = 35;
        else if (rarity == Rarity.Epic) base = 50;
        else base = 75;

        atk = base + ((seed >> 16) % (base / 2 + 1));
        def = base + ((seed >> 24) % (base / 2 + 1));
    }

    // ─── View Functions ──────────────────────────────────────────────

    /// @notice Get a player's card collection
    function getPlayerCards(address player) external view returns (uint256[] memory) {
        return playerCards[player];
    }

    /// @notice Get card stats
    function getCard(uint256 cardId) external view returns (uint256 atk, uint256 def, Element element, Rarity rarity) {
        Card storage c = cards[cardId];
        return (c.attack, c.defense, c.element, c.rarity);
    }

    /// @notice Get player win/loss record
    function getRecord(address player) external view returns (uint256 wins, uint256 losses) {
        return (playerWins[player], playerLosses[player]);
    }

    // ─── Admin ───────────────────────────────────────────────────────
    function setPackPrices(uint256 basicPrice, uint256 premiumPrice) external onlyOwner {
        basicPackPrice = basicPrice;
        premiumPackPrice = premiumPrice;
    }

    function withdraw() external onlyOwner nonReentrant {
        (bool success, ) = payable(owner).call{value: address(this).balance}("");
        require(success, "CardGame: withdraw failed");
    }

    receive() external payable {}
}
