// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "@openzeppelin-contracts-5.3.0/token/ERC20/IERC20.sol";
import "@openzeppelin-contracts-upgradeable-5.3.0/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import "@openzeppelin-contracts-upgradeable-5.3.0/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin-contracts-upgradeable-5.3.0/proxy/utils/Initializable.sol";
import "@openzeppelin-contracts-upgradeable-5.3.0/proxy/utils/UUPSUpgradeable.sol";
import "./tokens/NodeLicense.sol";

/**
 * @title NodeAsAService
 * @notice Contract for managing node rental payments and service records
 * @dev This contract handles USDC payments for node rentals and manages payment records
 */
contract NodeAsAService is 
    Initializable,
    AccessControlDefaultAdminRulesUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable 
{
    struct TokenAssignment {
        uint256 tokenId; // the token ids of the license
        bytes nodeId;  // Empty bytes if no nodeId assigned yet
    }

    struct PaymentRecord {
        address user;  // The user who owns this payment record
        uint256 licenseCount;  // Number of licenses being paid for
        bytes32 subnetId;  // The subnet this payment is for
        uint256 totalCumulativeDurationInSeconds;  // Duration in seconds
        uint256 totalAmountPaidInUSDC;  // Total amount paid in USDC
        uint256 startTime;  // When the payment started
        uint256 pricePerMonthAtPayment; // Price in USDC (6 decimals)
        TokenAssignment[100] tokenAssignments;  // Fixed size array for token assignments (max 100 licenses)
    }
    
    bytes32 public constant SCRIBE_ROLE = keccak256("SCRIBE_ROLE");
    bytes32 public constant PROTOCOL_MANAGER_ROLE = keccak256("PROTOCOL_MANAGER_ROLE");
    
    IERC20 public usdc;
    NodeLicense public nodeLicense;
    
    uint256 public licensePricePerMonth; // Price in USDC (6 decimals)
    
    mapping(address => PaymentRecord[]) public userPaymentRecords;
    
    event PaidForNodeServices(
        address indexed user,
        uint256 licenseCount,
        bytes32 subnetId,
        uint256 totalCumulativeDurationInSeconds,
        uint256 totalAmountPaidInUSDC,
        uint256 startTime,
        uint256 pricePerMonthAtPayment
    );
    event LicensePriceUpdated(uint256 oldPrice, uint256 newPrice);
    event TokenAssignmentUpdated(
        address indexed user,
        uint256 indexed paymentRecordIndex,
        uint256[] tokenIds,
        bytes[] nodeIds
    );
    
    error ZeroAddress();
    error InvalidPrice();
    error InsufficientBalance();
    error TransferFailed();
    error MustPayForAtLeastOneLicense();
    error DurationMustBeGreaterThanZero();
    error AmountMustBeGreaterThanZero();
    error InsufficientContractBalance();
    error InvalidPaymentRecordIndex();
    error EmptyTokenIds();
    error TokenIdNotFound();
    error TokenIdNodeIdMismatch();
    error TooManyLicenses();
    
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    
    /**
     * @notice Initializes the contract with required parameters
     * @param _usdc Address of the USDC token contract
     * @param _nodeLicense Address of the NodeLicense contract
     * @param _defaultAdmin Address that will have admin privileges
     * @param _scribe Address that will have scribe privileges
     * @param _initialPricePerMonth Initial price per month in USDC (6 decimals)
     */
    function initialize(
        address _usdc,
        address _nodeLicense,
        address _defaultAdmin,
        address _scribe,
        uint256 _initialPricePerMonth
    ) public initializer {
        if (_usdc == address(0) || _nodeLicense == address(0))
        {
            revert ZeroAddress();
        }
        if (_initialPricePerMonth == 0)
        {
            revert InvalidPrice();
        }
        
        __AccessControlDefaultAdminRules_init(0, _defaultAdmin);
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        
        _grantRole(SCRIBE_ROLE, _scribe);
        
        usdc = IERC20(_usdc);
        nodeLicense = NodeLicense(_nodeLicense);
        licensePricePerMonth = _initialPricePerMonth;
    }

    ///
    /// EXTERNAL FUNCTIONS - PAYMENT AND TOKEN MANAGEMENT
    ///
    
    /**
     * @notice Pays for node services per node license
     * @param licenseCount Number of licenses to pay for
     * @param totalCumulativeDurationInSeconds Total duration in seconds for all licenses
     * @param subnetId The ID of the subnet being paid for
     * @dev Requires USDC approval for the payment amount
     */
    function payForNodeServices(
        uint256 licenseCount, 
        uint256 totalCumulativeDurationInSeconds, 
        bytes32 subnetId
    ) external nonReentrant {
        if (licenseCount == 0)
        {
            revert MustPayForAtLeastOneLicense();
        }
        if (licenseCount > 100)
        {
            revert TooManyLicenses();
        }
        if (totalCumulativeDurationInSeconds == 0)
        {
            revert DurationMustBeGreaterThanZero();
        }
        
        // Calculate required payment
        uint256 requiredPayment = calculateRequiredPayment(licenseCount, totalCumulativeDurationInSeconds);
        if (usdc.balanceOf(msg.sender) < requiredPayment)
        {
            revert InsufficientBalance();
        }
        if (!usdc.transferFrom(msg.sender, address(this), requiredPayment))
        {
            revert TransferFailed();
        }
        
        uint256 startTime = block.timestamp;
        
        // Initialize payment record directly in storage
        PaymentRecord storage newPayment = userPaymentRecords[msg.sender].push();
        newPayment.user = msg.sender;
        newPayment.licenseCount = licenseCount;
        newPayment.subnetId = subnetId;
        newPayment.totalCumulativeDurationInSeconds = totalCumulativeDurationInSeconds;
        newPayment.totalAmountPaidInUSDC = requiredPayment;
        newPayment.startTime = startTime;
        newPayment.pricePerMonthAtPayment = licensePricePerMonth;
        
        // Initialize empty token assignments
        for (uint256 i = 0; i < 100; i++) {
            newPayment.tokenAssignments[i].tokenId = 0;
            newPayment.tokenAssignments[i].nodeId = bytes("");
        }
        
        emit PaidForNodeServices({
            user: msg.sender,
            licenseCount: licenseCount,
            subnetId: subnetId,
            totalCumulativeDurationInSeconds: totalCumulativeDurationInSeconds,
            totalAmountPaidInUSDC: requiredPayment,
            startTime: startTime,
            pricePerMonthAtPayment: licensePricePerMonth
        });
    }

    /**
     * @notice Adds tokenIDs and their corresponding nodeIDs to a specific payment record
     * @param user Address of the user whose payment record to update
     * @param paymentRecordIndex Index of the payment record to update
     * @param tokenIds Array of token IDs to add
     * @param nodeIds Array of nodeIDs corresponding to each tokenID (should be empty bytes if no nodeID is assigned yet)
     * @dev Only callable by scribes. Each tokenID must have a corresponding nodeID at the same index.
     */
    function addTokenAssignments(
        address user,
        uint256 paymentRecordIndex,
        uint256[] calldata tokenIds,
        bytes[] calldata nodeIds
    ) external onlyRole(SCRIBE_ROLE) {
        if (tokenIds.length == 0)
        {
            revert EmptyTokenIds();
        }
        if (tokenIds.length != nodeIds.length)
        {
            revert TokenIdNodeIdMismatch();
        }
        if (paymentRecordIndex >= userPaymentRecords[user].length)
        {
            revert InvalidPaymentRecordIndex();
        }

        PaymentRecord storage record = userPaymentRecords[user][paymentRecordIndex];
        
        // Add each tokenId and its nodeId
        for (uint256 i = 0; i < tokenIds.length; i++)
        {
            record.tokenAssignments[i] = TokenAssignment({
                tokenId: tokenIds[i],
                nodeId: nodeIds[i]
            });
        }

        emit TokenAssignmentUpdated({
            user: user,
            paymentRecordIndex: paymentRecordIndex,
            tokenIds: tokenIds,
            nodeIds: nodeIds
        });
    }

    /**
     * @notice Updates the nodeID for a specific tokenID in a payment record
     * @param user Address of the user whose payment record to update
     * @param paymentRecordIndex Index of the payment record to update
     * @param tokenId The token ID to update
     * @param nodeId The new nodeID to assign
     * @dev Only callable by scribes. Will revert if tokenId is not found.
     */
    function updateNodeId(
        address user,
        uint256 paymentRecordIndex,
        uint256 tokenId,
        bytes calldata nodeId
    ) external onlyRole(SCRIBE_ROLE) {
        if (paymentRecordIndex >= userPaymentRecords[user].length)
        {
            revert InvalidPaymentRecordIndex();
        }

        PaymentRecord storage record = userPaymentRecords[user][paymentRecordIndex];
        
        // Find the token assignment
        for (uint256 i = 0; i < record.licenseCount; i++) {
            if (record.tokenAssignments[i].tokenId == tokenId) {
                record.tokenAssignments[i].nodeId = nodeId;
                emit TokenAssignmentUpdated({
                    user: user,
                    paymentRecordIndex: paymentRecordIndex,
                    tokenIds: new uint256[](1),
                    nodeIds: new bytes[](1)
                });
                return;
            }
        }
        
        revert TokenIdNotFound();
    }

    /**
     * @notice Withdraws USDC from the contract
     * @param amount Amount of USDC to withdraw
     * @dev Only callable by protocol managers
     */
    function withdrawFunds(uint256 amount) external onlyRole(PROTOCOL_MANAGER_ROLE) nonReentrant {
        if (amount == 0)
        {
            revert AmountMustBeGreaterThanZero();
        }
        if (usdc.balanceOf(address(this)) < amount)
        {
            revert InsufficientContractBalance();
        }
        if (!usdc.transfer(msg.sender, amount))
        {
            revert TransferFailed();
        }
    }

    ///
    /// EXTERNAL FUNCTIONS - ADMIN AND CONFIGURATION
    ///

    /**
     * @notice Sets the price per month for licenses
     * @param _newPricePerMonth New price per month in USDC (6 decimals)
     * @dev Only callable by the default admin
     */
    function setLicensePricePerMonth(uint256 _newPricePerMonth) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_newPricePerMonth == 0)
        {
            revert InvalidPrice();
        }
        emit LicensePriceUpdated(licensePricePerMonth, _newPricePerMonth);
        licensePricePerMonth = _newPricePerMonth;
    }

    /**
     * @notice Grants the SCRIBE_ROLE to an address
     * @param scribe Address to grant scribe role to
     * @dev Only callable by the default admin
     */
    function setContractScribe(address scribe) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (scribe == address(0))
        {
            revert ZeroAddress();
        }
        _grantRole(SCRIBE_ROLE, scribe);
    }

    /**
     * @notice Grants the PROTOCOL_MANAGER_ROLE to an address
     * @param manager Address to grant protocol manager role to
     * @dev Only callable by the default admin
     */
    function setProtocolManager(address manager) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (manager == address(0))
        {
            revert ZeroAddress();
        }
        _grantRole(PROTOCOL_MANAGER_ROLE, manager);
    }

    ///
    /// PUBLIC VIEW FUNCTIONS
    ///

    /**
     * @notice Gets all payment records for a user
     * @param user Address of the user
     * @return Array of payment records
     */
    function getUserPaymentRecords(address user) external view returns (PaymentRecord[] memory) {
        return userPaymentRecords[user];
    }

    /**
     * @notice Gets the nodeID for a specific tokenID in a payment record
     * @param user Address of the user whose payment record to check
     * @param paymentRecordIndex Index of the payment record to check
     * @param tokenId The token ID to check
     * @return The nodeID assigned to the tokenID
     */
    function getNodeIdForToken(
        address user,
        uint256 paymentRecordIndex,
        uint256 tokenId
    ) external view returns (bytes memory) {
        if (paymentRecordIndex >= userPaymentRecords[user].length)
        {
            revert InvalidPaymentRecordIndex();
        }

        PaymentRecord storage record = userPaymentRecords[user][paymentRecordIndex];
        
        for (uint256 i = 0; i < record.licenseCount; i++) {
            if (record.tokenAssignments[i].tokenId == tokenId) {
                return record.tokenAssignments[i].nodeId;
            }
        }
        
        return bytes("");
    }

    /**
     * @notice Calculates the required USDC payment for node services
     * @param licenseCount Number of licenses to pay for
     * @param totalCumulativeDurationInSeconds Duration in seconds
     * @return Required payment amount in USDC
     */
    function calculateRequiredPayment(uint256 licenseCount, uint256 totalCumulativeDurationInSeconds) public view returns (uint256) {
        // Convert duration to months (rounding up to nearest month)
        uint256 secondsInMonth = 30 days;
        uint256 durationInMonths = (totalCumulativeDurationInSeconds + secondsInMonth - 1) / secondsInMonth;
        return licensePricePerMonth * durationInMonths * licenseCount;
    }

    /**
     * @notice Checks if contract supports an interface
     * @param interfaceId Interface ID to check
     * @return True if the interface is supported
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(AccessControlDefaultAdminRulesUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    ///
    /// INTERNAL FUNCTIONS
    ///

    /**
     * @notice Authorizes contract upgrade
     * @param newImplementation Address of the new implementation
     * @dev Only callable by the default admin
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}
