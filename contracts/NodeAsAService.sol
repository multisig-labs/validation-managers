// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "@openzeppelin-contracts-5.3.0/token/ERC20/IERC20.sol";
import "@openzeppelin-contracts-5.3.0/token/ERC20/utils/SafeERC20.sol";
import
  "@openzeppelin-contracts-upgradeable-5.3.0/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";

import "@openzeppelin-contracts-upgradeable-5.3.0/proxy/utils/Initializable.sol";
import "@openzeppelin-contracts-upgradeable-5.3.0/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin-contracts-upgradeable-5.3.0/utils/ReentrancyGuardUpgradeable.sol";

/**
 * @title NodeAsAService
 * @notice Contract for managing node rental payments and service records
 * @dev This contract handles USDC payments for node rentals and manages payment records
 */
struct PaymentRecord {
  uint8 licenseCount; // Number of licenses being paid for
  uint8 durationInMonths; // 1 Month = 30 days
  uint256 totalAmountPaidInUSDC; // Total amount paid in USDC
  uint256 pricePerMonthInUSDC; // Price per 30 days in USDC (6 decimals)
  address buyer; // The user who purchased the licenses
  bytes32 subnetId; // The subnet this payment is for
}

contract NodeAsAService is
  Initializable,
  AccessControlDefaultAdminRulesUpgradeable,
  ReentrancyGuardUpgradeable,
  UUPSUpgradeable
{
  using SafeERC20 for IERC20;

  bytes32 public constant PROTOCOL_MANAGER_ROLE = keccak256("PROTOCOL_MANAGER_ROLE");

  IERC20 public usdc;
  uint32 public invoiceNumber;
  uint256 public licensePricePerMonth; // Price in USDC (6 decimals) for a 30-day period
  bool public isPaused;

  mapping(uint32 invoiceNumber => PaymentRecord) public paymentRecord;
  mapping(address buyer => uint32[] invoiceNumbers) public buyerInvoices;

  event PaidForNodeServices(
    uint32 indexed invoiceNumber,
    address indexed buyer,
    bytes32 indexed subnetId,
    uint8 licenseCount,
    uint8 durationInMonths,
    uint256 totalAmountPaidInUSDC,
    uint256 priceAtPayment
  );
  event LicensePriceUpdated(uint256 oldPrice, uint256 newPrice);
  event PauseStateChanged(bool isPaused);

  error ZeroAddress();
  error InvalidPrice();
  error InsufficientBalance();
  error TransferFailed();
  error MustPayForAtLeastOneLicense();
  error DurationMustBeGreaterThanZero();
  error DurationMustBeMultipleOf30Days();
  error AmountMustBeGreaterThanZero();
  error InsufficientContractBalance();
  error InvalidPaymentRecordIndex();
  error ContractPaused();

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  /**
   * @notice Initializes the contract with required parameters
   * @param _usdc Address of the USDC token contract
   * @param _defaultAdmin Address that will have admin privileges
   * @param _initialPricePerMonthInUSDC Initial price for a 30-day period in USDC (6 decimals)
   */
  function initialize(
    address _usdc,
    address _defaultAdmin,
    uint256 _initialPricePerMonthInUSDC
  ) public initializer {
    if (_usdc == address(0)) {
      revert ZeroAddress();
    }
    if (_initialPricePerMonthInUSDC == 0) {
      revert InvalidPrice();
    }

    __AccessControlDefaultAdminRules_init(0, _defaultAdmin);
    __ReentrancyGuard_init();
    __UUPSUpgradeable_init();

    usdc = IERC20(_usdc);
    licensePricePerMonth = _initialPricePerMonthInUSDC;
    invoiceNumber = 1; // Initialize, e.g., to start invoices from 1
    isPaused = false;
  }

  ///
  /// EXTERNAL FUNCTIONS - PAYMENT AND TOKEN MANAGEMENT
  ///

  /**
   * @notice Pays for node services per node license
   * @param licenseCount Number of licenses to pay for
   * @param durationInMonths Total duration in months for each license
   * @param subnetId The ID of the subnet being paid for
   * @dev Requires USDC approval for the payment amount.
   */
  function payForNodeServices(uint8 licenseCount, uint8 durationInMonths, bytes32 subnetId)
    external
    nonReentrant
  {
    if (isPaused) {
      revert ContractPaused();
    }
    if (licenseCount == 0) {
      revert MustPayForAtLeastOneLicense();
    }
    if (durationInMonths == 0) {
      revert DurationMustBeGreaterThanZero();
    }

    // Calculate required payment
    uint256 requiredPayment = licensePricePerMonth * licenseCount * durationInMonths;
    if (usdc.balanceOf(msg.sender) < requiredPayment) {
      revert InsufficientBalance();
    }
    usdc.safeTransferFrom(msg.sender, address(this), requiredPayment);

    paymentRecord[invoiceNumber].buyer = msg.sender;
    paymentRecord[invoiceNumber].licenseCount = licenseCount;
    paymentRecord[invoiceNumber].subnetId = subnetId;
    paymentRecord[invoiceNumber].durationInMonths = durationInMonths;
    paymentRecord[invoiceNumber].totalAmountPaidInUSDC = requiredPayment;
    paymentRecord[invoiceNumber].pricePerMonthInUSDC = licensePricePerMonth;

    buyerInvoices[msg.sender].push(invoiceNumber);

    invoiceNumber++;

    emit PaidForNodeServices({
      invoiceNumber: invoiceNumber,
      buyer: msg.sender,
      licenseCount: licenseCount,
      subnetId: subnetId,
      durationInMonths: durationInMonths,
      totalAmountPaidInUSDC: requiredPayment,
      priceAtPayment: licensePricePerMonth
    });
  }

  /**
   * @notice Withdraws USDC from the contract
   * @param amount Amount of USDC to withdraw
   * @dev Only callable by protocol managers
   */
  function withdrawFunds(uint256 amount) external onlyRole(PROTOCOL_MANAGER_ROLE) nonReentrant {
    if (amount == 0) {
      revert AmountMustBeGreaterThanZero();
    }
    if (usdc.balanceOf(address(this)) < amount) {
      revert InsufficientContractBalance();
    }
    usdc.safeTransfer(msg.sender, amount);
  }

  ///
  /// EXTERNAL FUNCTIONS - ADMIN AND CONFIGURATION
  ///

  /**
   * @notice Sets the price per 30 days for licenses
   * @param _newPricePerMonth New price per 30 days in USDC (6 decimals)
   * @dev Only callable by the default admin
   */
  function setLicensePricePerMonth(uint256 _newPricePerMonth) external onlyRole(DEFAULT_ADMIN_ROLE) {
    if (_newPricePerMonth == 0) {
      revert InvalidPrice();
    }
    emit LicensePriceUpdated(licensePricePerMonth, _newPricePerMonth);
    licensePricePerMonth = _newPricePerMonth;
  }

  function setPaused(bool _isPaused) external onlyRole(PROTOCOL_MANAGER_ROLE) {
    isPaused = _isPaused;
    emit PauseStateChanged(_isPaused);
  }

  ///
  /// PUBLIC VIEW FUNCTIONS
  ///

  /**
   * @notice Gets all payment records for a user
   * @param _buyer Address of the purchaser
   * @return Array of invoice numbers
   */
  function getInvoiceNumbers(address _buyer) external view returns (uint32[] memory) {
    return buyerInvoices[_buyer];
  }

  function getPaymentRecord(uint32 _invoiceNumber) external view returns (PaymentRecord memory) {
    return paymentRecord[_invoiceNumber];
  }

  /**
   * @notice Checks if contract supports an interface
   * @param interfaceId Interface ID to check
   * @return True if the interface is supported
   */
  function supportsInterface(bytes4 interfaceId)
    public
    view
    override (AccessControlDefaultAdminRulesUpgradeable)
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
  function _authorizeUpgrade(address newImplementation)
    internal
    override
    onlyRole(DEFAULT_ADMIN_ROLE)
  { }
}