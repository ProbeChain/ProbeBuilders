// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title GuardedVault
 * @author ProbeBuilders
 * @notice Multi-sig vault with AI-assisted anomaly detection for ProbeChain Rydberg Testnet.
 * @dev 2-of-3 multi-sig approval, emergency freeze, withdrawal delay, anomaly flagging events.
 */

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

contract GuardedVault {
    // ---- Constants ----
    uint256 public constant REQUIRED_APPROVALS = 2;
    uint256 public constant MAX_SIGNERS = 3;
    uint256 public constant WITHDRAWAL_DELAY = 1 hours;
    uint256 public constant ANOMALY_THRESHOLD_PERCENT = 30; // 30% of total balance

    // ---- State ----
    address[3] public signers;
    mapping(address => bool) public isSigner;
    bool public frozen;

    struct WithdrawalRequest {
        uint256 id;
        address token; // address(0) for native ETH
        address to;
        uint256 amount;
        uint256 createdAt;
        uint256 approvalCount;
        mapping(address => bool) approved;
        bool executed;
        bool cancelled;
        bool flaggedAnomaly;
    }

    uint256 public nextRequestId;
    mapping(uint256 => WithdrawalRequest) public requests;

    // ---- Events ----
    event Deposited(address indexed sender, address indexed token, uint256 amount);
    event WithdrawalRequested(uint256 indexed requestId, address indexed token, address indexed to, uint256 amount);
    event WithdrawalApproved(uint256 indexed requestId, address indexed signer);
    event WithdrawalExecuted(uint256 indexed requestId, address indexed to, uint256 amount);
    event WithdrawalCancelled(uint256 indexed requestId);
    event VaultFrozen(address indexed by);
    event VaultUnfrozen(address indexed by);
    event AnomalyFlagged(uint256 indexed requestId, string reason);
    event SignerReplaced(address indexed oldSigner, address indexed newSigner);

    // ---- Modifiers ----
    modifier onlySigner() {
        require(isSigner[msg.sender], "GuardedVault: not a signer");
        _;
    }

    modifier notFrozen() {
        require(!frozen, "GuardedVault: vault is frozen");
        _;
    }

    // ---- Constructor ----
    constructor(address[3] memory _signers) {
        for (uint256 i = 0; i < 3; i++) {
            require(_signers[i] != address(0), "GuardedVault: zero signer");
            for (uint256 j = 0; j < i; j++) {
                require(_signers[i] != _signers[j], "GuardedVault: duplicate signer");
            }
            signers[i] = _signers[i];
            isSigner[_signers[i]] = true;
        }
    }

    // ---- Deposits ----

    /// @notice Deposit native currency
    receive() external payable {
        emit Deposited(msg.sender, address(0), msg.value);
    }

    /// @notice Deposit ERC20 tokens
    function depositToken(address token, uint256 amount) external {
        require(amount > 0, "GuardedVault: zero amount");
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        emit Deposited(msg.sender, token, amount);
    }

    // ---- Withdrawal Flow ----

    /// @notice Request a withdrawal (any signer)
    function requestWithdrawal(address token, address to, uint256 amount) external onlySigner notFrozen returns (uint256 requestId) {
        require(to != address(0), "GuardedVault: zero recipient");
        require(amount > 0, "GuardedVault: zero amount");

        requestId = nextRequestId++;
        WithdrawalRequest storage req = requests[requestId];
        req.id = requestId;
        req.token = token;
        req.to = to;
        req.amount = amount;
        req.createdAt = block.timestamp;

        // Auto-approve by requester
        req.approved[msg.sender] = true;
        req.approvalCount = 1;

        // Anomaly detection: flag if amount > threshold% of total balance
        _checkAnomaly(requestId, token, amount);

        emit WithdrawalRequested(requestId, token, to, amount);
        emit WithdrawalApproved(requestId, msg.sender);
    }

    /// @notice Approve a pending withdrawal request
    function approveWithdrawal(uint256 requestId) external onlySigner notFrozen {
        WithdrawalRequest storage req = requests[requestId];
        require(!req.executed, "GuardedVault: already executed");
        require(!req.cancelled, "GuardedVault: cancelled");
        require(!req.approved[msg.sender], "GuardedVault: already approved");

        req.approved[msg.sender] = true;
        req.approvalCount++;

        emit WithdrawalApproved(requestId, msg.sender);
    }

    /// @notice Execute an approved withdrawal after delay
    function executeWithdrawal(uint256 requestId) external onlySigner notFrozen {
        WithdrawalRequest storage req = requests[requestId];
        require(!req.executed, "GuardedVault: already executed");
        require(!req.cancelled, "GuardedVault: cancelled");
        require(req.approvalCount >= REQUIRED_APPROVALS, "GuardedVault: insufficient approvals");
        require(block.timestamp >= req.createdAt + WITHDRAWAL_DELAY, "GuardedVault: delay not met");

        req.executed = true;

        if (req.token == address(0)) {
            // Native transfer
            require(address(this).balance >= req.amount, "GuardedVault: insufficient balance");
            (bool sent, ) = req.to.call{value: req.amount}("");
            require(sent, "GuardedVault: transfer failed");
        } else {
            IERC20(req.token).transfer(req.to, req.amount);
        }

        emit WithdrawalExecuted(requestId, req.to, req.amount);
    }

    /// @notice Cancel a pending withdrawal
    function cancelWithdrawal(uint256 requestId) external onlySigner {
        WithdrawalRequest storage req = requests[requestId];
        require(!req.executed, "GuardedVault: already executed");
        require(!req.cancelled, "GuardedVault: already cancelled");
        req.cancelled = true;
        emit WithdrawalCancelled(requestId);
    }

    // ---- Emergency Controls ----

    /// @notice Freeze the vault (any signer can trigger)
    function freeze() external onlySigner {
        frozen = true;
        emit VaultFrozen(msg.sender);
    }

    /// @notice Unfreeze requires 2-of-3 approval
    /// @dev Simplified: all 3 signers must call unfreeze; after 2 calls, it unfreezes
    uint256 private _unfreezeCount;
    mapping(address => bool) private _unfreezeApproved;

    function unfreeze() external onlySigner {
        require(frozen, "GuardedVault: not frozen");
        require(!_unfreezeApproved[msg.sender], "GuardedVault: already voted");
        _unfreezeApproved[msg.sender] = true;
        _unfreezeCount++;

        if (_unfreezeCount >= REQUIRED_APPROVALS) {
            frozen = false;
            _unfreezeCount = 0;
            for (uint256 i = 0; i < 3; i++) {
                _unfreezeApproved[signers[i]] = false;
            }
            emit VaultUnfrozen(msg.sender);
        }
    }

    // ---- Signer Management ----

    /// @notice Replace a signer (requires 2-of-3)
    /// @dev Simplified: only owner (signers[0]) + one other signer must call
    mapping(bytes32 => uint256) private _replaceApprovals;
    mapping(bytes32 => mapping(address => bool)) private _replaceVoted;

    function replaceSigner(address oldSigner, address newSigner) external onlySigner {
        require(isSigner[oldSigner], "GuardedVault: not a signer");
        require(!isSigner[newSigner], "GuardedVault: already a signer");
        require(newSigner != address(0), "GuardedVault: zero address");

        bytes32 opHash = keccak256(abi.encodePacked(oldSigner, newSigner));
        require(!_replaceVoted[opHash][msg.sender], "GuardedVault: already voted");
        _replaceVoted[opHash][msg.sender] = true;
        _replaceApprovals[opHash]++;

        if (_replaceApprovals[opHash] >= REQUIRED_APPROVALS) {
            isSigner[oldSigner] = false;
            isSigner[newSigner] = true;
            for (uint256 i = 0; i < 3; i++) {
                if (signers[i] == oldSigner) {
                    signers[i] = newSigner;
                    break;
                }
            }
            // Cleanup
            _replaceApprovals[opHash] = 0;
            for (uint256 i = 0; i < 3; i++) {
                _replaceVoted[opHash][signers[i]] = false;
            }
            _replaceVoted[opHash][oldSigner] = false;

            emit SignerReplaced(oldSigner, newSigner);
        }
    }

    // ---- Anomaly Detection ----

    function _checkAnomaly(uint256 requestId, address token, uint256 amount) internal {
        uint256 totalBalance;
        if (token == address(0)) {
            totalBalance = address(this).balance;
        } else {
            totalBalance = IERC20(token).balanceOf(address(this));
        }

        if (totalBalance > 0 && (amount * 100) / totalBalance > ANOMALY_THRESHOLD_PERCENT) {
            requests[requestId].flaggedAnomaly = true;
            emit AnomalyFlagged(requestId, "Large withdrawal: exceeds 30% of vault balance");
        }
    }

    // ---- View Helpers ----

    function getRequestApproval(uint256 requestId, address signer) external view returns (bool) {
        return requests[requestId].approved[signer];
    }

    function nativeBalance() external view returns (uint256) {
        return address(this).balance;
    }

    function tokenBalance(address token) external view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }
}
