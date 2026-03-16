// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title UpgradeableProxy
 * @author ProbeChain Team
 * @notice Transparent upgradeable proxy pattern for contract upgradeability
 * @dev Admin can upgrade implementation; all other calls delegated to implementation
 *
 * Storage slots follow EIP-1967 for collision avoidance:
 *   - Implementation: bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1)
 *   - Admin:          bytes32(uint256(keccak256("eip1967.proxy.admin")) - 1)
 */
contract UpgradeableProxy {
    // ─── EIP-1967 Storage Slots ─────────────────────────────────────────
    /**
     * @dev Storage slot with the address of the current implementation.
     * bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1)
     */
    bytes32 private constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    /**
     * @dev Storage slot with the admin of the proxy.
     * bytes32(uint256(keccak256("eip1967.proxy.admin")) - 1)
     */
    bytes32 private constant ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    /**
     * @dev Storage slot with the pending admin for two-step transfer.
     * bytes32(uint256(keccak256("eip1967.proxy.pendingAdmin")) - 1)
     */
    bytes32 private constant PENDING_ADMIN_SLOT = 0x54ac2bd5363dfe95a011c5b5f837584b064e63b41b86b0e5b87e5e55616e1c22;

    // ─── Events ─────────────────────────────────────────────────────────
    /// @notice Emitted when the implementation is upgraded
    event Upgraded(address indexed implementation);
    /// @notice Emitted when admin is changed
    event AdminChanged(address indexed previousAdmin, address indexed newAdmin);
    /// @notice Emitted when a pending admin is proposed
    event AdminChangeProposed(address indexed currentAdmin, address indexed pendingAdmin);

    // ─── Constructor ────────────────────────────────────────────────────
    /**
     * @notice Deploy the proxy with an initial implementation and admin
     * @param initialImplementation Address of the initial logic contract
     * @param initialAdmin Admin address (can upgrade)
     * @param initData Optional initialization calldata (empty for no init)
     */
    constructor(
        address initialImplementation,
        address initialAdmin,
        bytes memory initData
    ) {
        require(initialImplementation != address(0), "UpgradeableProxy: zero implementation");
        require(initialAdmin != address(0), "UpgradeableProxy: zero admin");
        require(_isContract(initialImplementation), "UpgradeableProxy: not a contract");

        _setImplementation(initialImplementation);
        _setAdmin(initialAdmin);

        if (initData.length > 0) {
            (bool success, bytes memory returndata) = initialImplementation.delegatecall(initData);
            require(success, string(abi.encodePacked("UpgradeableProxy: init failed: ", returndata)));
        }

        emit Upgraded(initialImplementation);
        emit AdminChanged(address(0), initialAdmin);
    }

    // ─── Admin Functions (only callable by admin) ───────────────────────
    /**
     * @notice Upgrade the implementation to a new contract
     * @param newImplementation Address of the new logic contract
     */
    function upgradeTo(address newImplementation) external {
        require(msg.sender == _getAdmin(), "UpgradeableProxy: caller is not admin");
        require(newImplementation != address(0), "UpgradeableProxy: zero address");
        require(_isContract(newImplementation), "UpgradeableProxy: not a contract");
        require(newImplementation != _getImplementation(), "UpgradeableProxy: same implementation");

        _setImplementation(newImplementation);
        emit Upgraded(newImplementation);
    }

    /**
     * @notice Upgrade and call an initialization function on the new implementation
     * @param newImplementation New implementation address
     * @param data Initialization calldata
     */
    function upgradeToAndCall(address newImplementation, bytes calldata data) external payable {
        require(msg.sender == _getAdmin(), "UpgradeableProxy: caller is not admin");
        require(newImplementation != address(0), "UpgradeableProxy: zero address");
        require(_isContract(newImplementation), "UpgradeableProxy: not a contract");

        _setImplementation(newImplementation);
        emit Upgraded(newImplementation);

        if (data.length > 0) {
            (bool success, ) = newImplementation.delegatecall(data);
            require(success, "UpgradeableProxy: call failed");
        }
    }

    /**
     * @notice Get the current implementation address
     * @return impl Implementation address
     */
    function getImplementation() external view returns (address impl) {
        require(msg.sender == _getAdmin(), "UpgradeableProxy: admin only");
        return _getImplementation();
    }

    /**
     * @notice Get the current admin address
     * @return adm Admin address
     */
    function getAdmin() external view returns (address adm) {
        require(msg.sender == _getAdmin(), "UpgradeableProxy: admin only");
        return _getAdmin();
    }

    /**
     * @notice Propose a new admin (two-step transfer)
     * @param newAdmin Proposed new admin
     */
    function changeAdmin(address newAdmin) external {
        require(msg.sender == _getAdmin(), "UpgradeableProxy: caller is not admin");
        require(newAdmin != address(0), "UpgradeableProxy: zero address");

        _setPendingAdmin(newAdmin);
        emit AdminChangeProposed(_getAdmin(), newAdmin);
    }

    /**
     * @notice Accept admin role (called by pending admin)
     */
    function acceptAdmin() external {
        require(msg.sender == _getPendingAdmin(), "UpgradeableProxy: not pending admin");

        address previousAdmin = _getAdmin();
        _setAdmin(msg.sender);
        _setPendingAdmin(address(0));

        emit AdminChanged(previousAdmin, msg.sender);
    }

    // ─── Fallback: Delegate to Implementation ──────────────────────────
    /**
     * @dev Delegates all calls to the implementation contract
     */
    fallback() external payable {
        _delegate(_getImplementation());
    }

    /**
     * @dev Receives native tokens
     */
    receive() external payable {
        _delegate(_getImplementation());
    }

    // ─── Internal Functions ─────────────────────────────────────────────
    /**
     * @dev Delegate call to the implementation
     * @param implementation Target implementation address
     */
    function _delegate(address implementation) internal {
        assembly {
            // Copy msg.data
            calldatacopy(0, 0, calldatasize())

            // Delegatecall to the implementation
            let result := delegatecall(gas(), implementation, 0, calldatasize(), 0, 0)

            // Copy the returned data
            returndatacopy(0, 0, returndatasize())

            switch result
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }

    function _getImplementation() internal view returns (address impl) {
        bytes32 slot = IMPLEMENTATION_SLOT;
        assembly {
            impl := sload(slot)
        }
    }

    function _setImplementation(address newImplementation) internal {
        bytes32 slot = IMPLEMENTATION_SLOT;
        assembly {
            sstore(slot, newImplementation)
        }
    }

    function _getAdmin() internal view returns (address adm) {
        bytes32 slot = ADMIN_SLOT;
        assembly {
            adm := sload(slot)
        }
    }

    function _setAdmin(address newAdmin) internal {
        bytes32 slot = ADMIN_SLOT;
        assembly {
            sstore(slot, newAdmin)
        }
    }

    function _getPendingAdmin() internal view returns (address pending) {
        bytes32 slot = PENDING_ADMIN_SLOT;
        assembly {
            pending := sload(slot)
        }
    }

    function _setPendingAdmin(address newPending) internal {
        bytes32 slot = PENDING_ADMIN_SLOT;
        assembly {
            sstore(slot, newPending)
        }
    }

    /**
     * @dev Check if an address is a contract
     * @param account Address to check
     * @return isContract True if the address has code
     */
    function _isContract(address account) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }
}
