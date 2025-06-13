// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "@openzeppelin-contracts-5.3.0/token/ERC20/IERC20.sol";
import "@openzeppelin-contracts-5.3.0/token/ERC20/utils/SafeERC20.sol";
import
  "@openzeppelin-contracts-upgradeable-5.3.0/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";

import "@openzeppelin-contracts-upgradeable-5.3.0/proxy/utils/Initializable.sol";
import "@openzeppelin-contracts-upgradeable-5.3.0/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin-contracts-upgradeable-5.3.0/utils/ReentrancyGuardUpgradeable.sol";

import { AggregatorV3Interface } from
  "chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

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
  address public treasury;

  mapping(uint32 invoiceNumber => PaymentRecord) public paymentRecord;
  mapping(address buyer => uint32[] invoiceNumbers) public buyerInvoices;

  // Decimal scaling factor
  // AVAX_DECIMALS = 18;
  // USD_PRICE_DECIMALS = 18;
  // USDC_DECIMALS = 6;
  // DECIMAL_SCALING_FACTOR = 10 ** (AVAX_DECIMALS + USD_PRICE_DECIMALS - USDC_DECIMALS);
  uint256 private constant DECIMAL_SCALING_FACTOR = 10 ** (18 + 18 - 6); // 1e30

  uint256 public payAsYouGoFeePerMonth; // Fee in AVAX that is required per node per month
  address public avaxPriceFeed;

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
  event PayAsYouGoFeeUpdated(uint256 oldFee, uint256 newFee);
  event PauseStateChanged(bool isPaused);

  error ZeroAddress();
  error InvalidPrice();
  error InsufficientBalance();
  error MustPayForAtLeastOneLicense();
  error DurationMustBeGreaterThanZero();
  error AmountMustBeGreaterThanZero();
  error InsufficientContractBalance();
  error ContractPaused();
  error InvalidTreasuryAddress();

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  /**
   * @notice Initializes the contract with required parameters for new deployments
   * @param _usdc Address of the USDC token contract
   * @param _defaultAdmin Address that will have admin privileges
   * @param _initialPricePerMonthInUSDC Initial price for a 30-day period in USDC (6 decimals)
   * @param _treasury Address of the treasury
   * @param _avaxPriceFeed Address of the AVAX price feed
   * @param _payAsYouGoFeePerMonth Initial pay as you go fee per month in AVAX (18 decimals)
   */
  function initialize(
    address _usdc,
    address _defaultAdmin,
    uint256 _initialPricePerMonthInUSDC,
    address _treasury,
    address _avaxPriceFeed,
    uint256 _payAsYouGoFeePerMonth
  ) public initializer {
    if (_usdc == address(0)) {
      revert ZeroAddress();
    }
    if (_initialPricePerMonthInUSDC == 0) {
      revert InvalidPrice();
    }
    if (_treasury == address(0)) {
      revert InvalidTreasuryAddress();
    }

    __AccessControlDefaultAdminRules_init(0, _defaultAdmin);
    __ReentrancyGuard_init();
    __UUPSUpgradeable_init();

    usdc = IERC20(_usdc);
    licensePricePerMonth = _initialPricePerMonthInUSDC;
    invoiceNumber = 1; // Initialize, e.g., to start invoices from 1
    isPaused = false;
    treasury = _treasury;
    avaxPriceFeed = _avaxPriceFeed;
    payAsYouGoFeePerMonth = _payAsYouGoFeePerMonth;
  }

  /**
   * @notice Initializes V2 specific features during upgrade from V1
   * @param _avaxPriceFeed Address of the AVAX price feed
   * @param _payAsYouGoFeePerMonth Initial pay as you go fee per month in AVAX (18 decimals)
   * @dev Only sets new V2 variables, doesn't reinitialize existing systems
   */
  function initializeV2(address _avaxPriceFeed, uint256 _payAsYouGoFeePerMonth)
    public
    reinitializer(2)
  {
    avaxPriceFeed = _avaxPriceFeed;
    payAsYouGoFeePerMonth = _payAsYouGoFeePerMonth;
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

    // Calculate monthly PAYG fee in USDC (6 decimals)
    // payAsYouGoFeePerMonth is in AVAX (18 decimals)
    // getAvaxUsdPrice() returns price in USD (18 decimals)
    // We need result in USDC (6 decimals)
    // Formula: (AVAX_amount * USD_price_per_AVAX) / scaling_factor = USDC_amount
    uint256 monthlyPAYGFee = (payAsYouGoFeePerMonth * getAvaxUsdPrice()) / DECIMAL_SCALING_FACTOR;

    uint256 totalMonthlyFee = licensePricePerMonth + monthlyPAYGFee;

    // Calculate required payment
    uint256 requiredPayment = totalMonthlyFee * licenseCount * durationInMonths;

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
   * @notice Withdraws USDC from the contract to the treasury
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
    usdc.safeTransfer(treasury, amount);
  }

  ///
  /// EXTERNAL FUNCTIONS - ADMIN AND CONFIGURATION
  ///

  /**
   * @notice Sets the price per 30 days for licenses
   * @param _newPricePerMonth New price per 30 days in USDC (6 decimals)
   * @dev Only callable by the protocol manager
   */
  function setLicensePricePerMonth(uint256 _newPricePerMonth)
    external
    onlyRole(PROTOCOL_MANAGER_ROLE)
  {
    if (_newPricePerMonth == 0) {
      revert InvalidPrice();
    }
    emit LicensePriceUpdated(licensePricePerMonth, _newPricePerMonth);
    licensePricePerMonth = _newPricePerMonth;
  }

  /**
   * @notice Sets the pay as you go fee per month
   * @param _payAsYouGoFeePerMonth New pay as you go fee per month in AVAX (18 decimals)
   * @dev Only callable by the protocol manager
   */
  function setPayAsYouGoFeePerMonth(uint256 _payAsYouGoFeePerMonth)
    external
    onlyRole(PROTOCOL_MANAGER_ROLE)
  {
    emit PayAsYouGoFeeUpdated(payAsYouGoFeePerMonth, _payAsYouGoFeePerMonth);
    payAsYouGoFeePerMonth = _payAsYouGoFeePerMonth;
  }

  /**
   * @notice Sets the paused state of the contract
   * @param _isPaused New paused state
   * @dev Only callable by the protocol manager
   */
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
   * @notice Get the price of AVAX in USD from chainlink aggregator
   * @return price The price of AVAX in USD
   */
  function getAvaxUsdPrice() public view returns (uint256) {
    (, int256 answer,,,) = AggregatorV3Interface(avaxPriceFeed).latestRoundData();
    uint8 decimals = AggregatorV3Interface(avaxPriceFeed).decimals();
    uint256 scalingFactor = 18 - decimals;
    return uint256(answer) * 10 ** scalingFactor;
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
