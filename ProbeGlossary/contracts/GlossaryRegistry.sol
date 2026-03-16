// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title GlossaryRegistry
 * @author ProbeChain Team
 * @notice On-chain terminology registry with multi-language translation support
 * @dev Community-maintained glossary with category-based search and translations
 */
contract GlossaryRegistry {
    // ─── Ownable ────────────────────────────────────────────────────────
    address private _owner;
    modifier onlyOwner() {
        require(msg.sender == _owner, "GlossaryRegistry: caller is not owner");
        _;
    }
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    function owner() public view returns (address) { return _owner; }
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "GlossaryRegistry: zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }

    // ─── Pausable ───────────────────────────────────────────────────────
    bool private _paused;
    modifier whenNotPaused() { require(!_paused, "GlossaryRegistry: paused"); _; }
    function paused() public view returns (bool) { return _paused; }
    function pause() external onlyOwner { _paused = true; emit Paused(msg.sender); }
    function unpause() external onlyOwner { _paused = false; emit Unpaused(msg.sender); }
    event Paused(address account);
    event Unpaused(address account);

    // ─── Structs ────────────────────────────────────────────────────────
    struct Term {
        uint256 id;
        string term;
        string definition;
        string category;
        string language;
        address author;
        uint256 translationCount;
        uint256 createdAt;
        uint256 updatedAt;
        bool active;
    }

    struct Translation {
        uint256 id;
        uint256 termId;
        string language;
        string translatedTerm;
        string translatedDefinition;
        address translator;
        uint256 createdAt;
    }

    // ─── State ──────────────────────────────────────────────────────────
    uint256 public termCount;
    uint256 public translationCount;

    mapping(uint256 => Term) public terms;
    mapping(uint256 => Translation) public translations;
    mapping(uint256 => uint256[]) public termTranslations;
    mapping(string => uint256[]) public categoryTerms;
    mapping(string => uint256[]) public languageTerms;
    mapping(address => uint256[]) public authorTerms;
    mapping(address => uint256) public contributorPoints;
    mapping(address => bool) public trustedEditors;

    // ─── Events ─────────────────────────────────────────────────────────
    /// @notice Emitted when a new term is added
    event TermAdded(uint256 indexed termId, string term, string category, string language, address indexed author);
    /// @notice Emitted when a term is updated
    event TermUpdated(uint256 indexed termId, string newDefinition, address indexed editor);
    /// @notice Emitted when a translation is added
    event TermTranslated(uint256 indexed translationId, uint256 indexed termId, string language, address indexed translator);
    /// @notice Emitted when a term is deactivated
    event TermDeactivated(uint256 indexed termId);
    /// @notice Emitted when editor trust status changes
    event EditorTrustSet(address indexed editor, bool trusted);

    // ─── Constructor ────────────────────────────────────────────────────
    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    // ─── Editor Management ──────────────────────────────────────────────
    /**
     * @notice Set trusted editor status
     * @param editor Editor address
     * @param trusted Whether to trust
     */
    function setTrustedEditor(address editor, bool trusted) external onlyOwner {
        trustedEditors[editor] = trusted;
        emit EditorTrustSet(editor, trusted);
    }

    // ─── Core Functions ─────────────────────────────────────────────────
    /**
     * @notice Add a new term to the glossary
     * @param term The term string
     * @param definition Definition text
     * @param category Category (e.g., "DeFi", "Consensus", "Cryptography")
     * @param language Language code (e.g., "en", "zh", "ja")
     */
    function addTerm(
        string calldata term,
        string calldata definition,
        string calldata category,
        string calldata language
    ) external whenNotPaused {
        require(bytes(term).length > 0 && bytes(term).length <= 128, "GlossaryRegistry: invalid term");
        require(bytes(definition).length > 0 && bytes(definition).length <= 1024, "GlossaryRegistry: invalid definition");
        require(bytes(category).length > 0, "GlossaryRegistry: empty category");
        require(bytes(language).length >= 2, "GlossaryRegistry: invalid language");

        termCount++;
        terms[termCount] = Term({
            id: termCount,
            term: term,
            definition: definition,
            category: category,
            language: language,
            author: msg.sender,
            translationCount: 0,
            createdAt: block.timestamp,
            updatedAt: block.timestamp,
            active: true
        });

        categoryTerms[category].push(termCount);
        languageTerms[language].push(termCount);
        authorTerms[msg.sender].push(termCount);
        contributorPoints[msg.sender] += 10;

        emit TermAdded(termCount, term, category, language, msg.sender);
    }

    /**
     * @notice Update a term's definition
     * @param termId Term to update
     * @param newDefinition New definition text
     */
    function updateTerm(uint256 termId, string calldata newDefinition) external whenNotPaused {
        Term storage t = terms[termId];
        require(t.active, "GlossaryRegistry: term not active");
        require(
            msg.sender == t.author || trustedEditors[msg.sender] || msg.sender == _owner,
            "GlossaryRegistry: unauthorized"
        );
        require(bytes(newDefinition).length > 0 && bytes(newDefinition).length <= 1024, "GlossaryRegistry: invalid definition");

        t.definition = newDefinition;
        t.updatedAt = block.timestamp;
        contributorPoints[msg.sender] += 5;

        emit TermUpdated(termId, newDefinition, msg.sender);
    }

    /**
     * @notice Add a translation for an existing term
     * @param termId Term to translate
     * @param language Target language code
     * @param translatedTerm Translated term
     * @param translatedDefinition Translated definition
     */
    function translateTerm(
        uint256 termId,
        string calldata language,
        string calldata translatedTerm,
        string calldata translatedDefinition
    ) external whenNotPaused {
        Term storage t = terms[termId];
        require(t.active, "GlossaryRegistry: term not active");
        require(bytes(language).length >= 2, "GlossaryRegistry: invalid language");
        require(bytes(translatedTerm).length > 0, "GlossaryRegistry: empty translation");
        require(bytes(translatedDefinition).length > 0, "GlossaryRegistry: empty definition");

        translationCount++;
        translations[translationCount] = Translation({
            id: translationCount,
            termId: termId,
            language: language,
            translatedTerm: translatedTerm,
            translatedDefinition: translatedDefinition,
            translator: msg.sender,
            createdAt: block.timestamp
        });

        t.translationCount++;
        termTranslations[termId].push(translationCount);
        contributorPoints[msg.sender] += 8;

        emit TermTranslated(translationCount, termId, language, msg.sender);
    }

    /**
     * @notice Search terms by category (returns up to 20 IDs)
     * @param category Category to search
     * @return ids Array of term IDs
     */
    function searchTerms(string calldata category) external view returns (uint256[] memory ids) {
        uint256[] storage catTerms = categoryTerms[category];
        uint256 len = catTerms.length > 20 ? 20 : catTerms.length;
        ids = new uint256[](len);
        for (uint256 i = 0; i < len; i++) {
            ids[i] = catTerms[catTerms.length - 1 - i];
        }
    }

    /**
     * @notice Get translations for a term
     * @param termId Term ID
     * @return translationIds Array of translation IDs
     */
    function getTranslations(uint256 termId) external view returns (uint256[] memory translationIds) {
        return termTranslations[termId];
    }

    /**
     * @notice Deactivate a term
     * @param termId Term to deactivate
     */
    function deactivateTerm(uint256 termId) external {
        require(
            terms[termId].author == msg.sender || msg.sender == _owner,
            "GlossaryRegistry: unauthorized"
        );
        terms[termId].active = false;
        emit TermDeactivated(termId);
    }

    /**
     * @notice Get contributor points
     * @param contributor Contributor address
     * @return points Total points
     */
    function getContributorPoints(address contributor) external view returns (uint256 points) {
        return contributorPoints[contributor];
    }
}
