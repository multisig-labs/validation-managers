// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title BasicLicenseSale
/// @notice Contract for managing the sale of licenses with USDC as payment token
/// @dev Implements whitelist functionality and uses USDC for payments
contract BasicLicenseSale is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    
    /// @notice Treasury address where collected funds are sent
    address public immutable treasury;
    
    /// @notice USDC token contract address
    IERC20 public immutable usdc;
    
    /// @notice Price per license in USDC (6 decimals)
    uint256 public price = 10_000; // 0.01 USDC (1 cent)
    
    /// @notice Maximum number of licenses a single address can purchase
    uint256 public maxLicenses = 250;
    
    /// @notice Maximum total number of licenses that can be sold
    uint256 public maxTotalSupply = 1000;
    
    /// @notice Total number of licenses sold
    uint256 public supply;
    
    /// @notice Flag indicating if sales are currently active
    bool public salesActive = true;
    
    /// @notice Flag indicating if whitelist functionality is enabled
    bool public isWhitelistEnabled = false;

    /// @notice List of all addresses that have purchased licenses
    address[] public buyers;

    /// @notice Mapping of addresses to their whitelist status
    mapping(address => bool) public whitelist;
    
    /// @notice Mapping of addresses to number of licenses purchased
    mapping(address => uint256) public licensesPurchased;

    /// @notice Emitted when a license is purchased
    /// @param buyer Address of the buyer
    /// @param amount Number of licenses purchased
    /// @param totalCost Total cost paid in USDC
    event LicensePurchased(address buyer, uint256 amount, uint256 totalCost);
    
    /// @notice Emitted when an address is added to whitelist
    /// @param user Address added to whitelist
    event WhitelistAdded(address user);
    
    /// @notice Emitted when an address is removed from whitelist
    /// @param user Address removed from whitelist
    event WhitelistRemoved(address user);
    
    /// @notice Emitted when the license price is updated
    /// @param newPrice New price per license
    event PriceUpdated(uint256 newPrice);
    
    /// @notice Emitted when sales status is changed
    /// @param isActive New sales status
    event SalesStatusChanged(bool isActive);
    
    /// @notice Emitted when whitelist status is changed
    /// @param isEnabled New whitelist status
    event WhitelistStatusChanged(bool isEnabled);
    
    /// @notice Emitted when maximum licenses per address is updated
    /// @param newMaxLicenses New maximum licenses limit
    event MaxLicensesUpdated(uint256 newMaxLicenses);

    /// @notice Emitted when maximum total supply is updated
    /// @param newMaxTotalSupply New maximum total supply limit
    event MaxTotalSupplyUpdated(uint256 newMaxTotalSupply);

    /// @notice Custom errors
    error InvalidUSDCAddress();
    error InvalidTreasuryAddress();
    error SalesNotActive();
    error NotWhitelisted();
    error ExceedsMaxLicenses();
    error ExceedsMaxTotalSupply();
    error InsufficientUSDCAllowance();
    error InsufficientUSDCBalance();

    /// @notice Constructor initializes the contract with the deployer as owner and sets USDC address
    /// @param usdcAddress Address of the USDC token contract
    /// @param treasuryAddress Address where collected funds will be sent
    constructor(address usdcAddress, address treasuryAddress) Ownable(msg.sender) {
        if (usdcAddress == address(0)) revert InvalidUSDCAddress();
        if (treasuryAddress == address(0)) revert InvalidTreasuryAddress();
        usdc = IERC20(usdcAddress);
        treasury = treasuryAddress;
    }

    /// @notice Purchase licenses using USDC
    /// @dev Checks for whitelist if enabled, verifies USDC allowance and balance
    /// @param licenseAmount Number of licenses to purchase
    function buy(uint256 licenseAmount) external nonReentrant {
        if (!salesActive) revert SalesNotActive();
        if (isWhitelistEnabled && !whitelist[msg.sender]) revert NotWhitelisted();
        if (licensesPurchased[msg.sender] + licenseAmount > maxLicenses) revert ExceedsMaxLicenses();
        if (supply + licenseAmount > maxTotalSupply) revert ExceedsMaxTotalSupply();
        
        uint256 totalPrice = price * licenseAmount;
        if (usdc.allowance(msg.sender, address(this)) < totalPrice) revert InsufficientUSDCAllowance();
        if (usdc.balanceOf(msg.sender) < totalPrice) revert InsufficientUSDCBalance();
        
        usdc.safeTransferFrom(msg.sender, address(this), totalPrice);
        
        if (licensesPurchased[msg.sender] == 0) {
            buyers.push(msg.sender);
        }
        licensesPurchased[msg.sender] += licenseAmount;
        supply += licenseAmount;
        emit LicensePurchased(msg.sender, licenseAmount, totalPrice);
    }

    /// @notice Enable or disable whitelist functionality
    /// @dev Only callable by owner
    /// @param enabled New whitelist status
    function setWhitelistEnabled(bool enabled) external onlyOwner {
        isWhitelistEnabled = enabled;
        emit WhitelistStatusChanged(enabled);
    }
    
    /// @notice Update the price per license
    /// @dev Only callable by owner
    /// @param newPrice New price per license in USDC (6 decimals)
    function setLicensePrice(uint256 newPrice) external onlyOwner {
        price = newPrice;
        emit PriceUpdated(newPrice);
    }
    
    /// @notice Add an address to the whitelist
    /// @dev Only callable by owner
    /// @param user Address to add to whitelist
    function addToWhitelist(address user) external onlyOwner {
        whitelist[user] = true;
        emit WhitelistAdded(user);
    }
    
    /// @notice Remove an address from the whitelist
    /// @dev Only callable by owner
    /// @param user Address to remove from whitelist
    function removeFromWhitelist(address user) external onlyOwner {
        whitelist[user] = false;
        emit WhitelistRemoved(user);
    }
    
    /// @notice Stop license sales
    /// @dev Only callable by owner
    function stopLicenseSales() external onlyOwner {
        salesActive = false;
        emit SalesStatusChanged(false);
    }
    
    /// @notice Start license sales
    /// @dev Only callable by owner
    function startLicenseSales() external onlyOwner {
        salesActive = true;
        emit SalesStatusChanged(true);
    }

    /// @notice Update maximum licenses per address
    /// @dev Only callable by owner
    /// @param newMaxLicenses New maximum licenses limit
    function setMaxLicensesPerAddress(uint256 newMaxLicenses) external onlyOwner {
        maxLicenses = newMaxLicenses;
        emit MaxLicensesUpdated(newMaxLicenses);
    }

    /// @notice Withdraw all collected USDC to treasury
    /// @dev Only callable by owner
    function withdrawToTreasury() external onlyOwner {
        uint256 balance = usdc.balanceOf(address(this));
        if (balance > 0) {
            usdc.safeTransfer(treasury, balance);
        }
    }

    /// @notice Update maximum total supply
    /// @dev Only callable by owner
    /// @param newMaxTotalSupply New maximum total supply limit
    function setMaxTotalSupply(uint256 newMaxTotalSupply) external onlyOwner {
        maxTotalSupply = newMaxTotalSupply;
        emit MaxTotalSupplyUpdated(newMaxTotalSupply);
    }

    /// @notice Get list of all buyers and their license counts
    /// @return Array of buyer addresses
    /// @return Array of corresponding license counts
    function getAllBuyers() external view returns (address[] memory, uint256[] memory) {
        uint256[] memory counts = new uint256[](buyers.length);
        for (uint i; i < buyers.length; i++) {
            counts[i] = licensesPurchased[buyers[i]];
        }
        return (buyers, counts);
    }
}