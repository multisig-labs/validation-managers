// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title BasicNodeSale
/// @notice Contract for managing the sale of nodes with USDC as payment token
/// @dev Implements whitelist functionality and uses USDC for payments
contract BasicNodeSale is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    
    /// @notice Treasury address where collected funds are sent
    address constant TREASURY = 0x1E3D04c315eDBb584A9fB85F5Aa30d6385a6859C;
    
    /// @notice USDC token contract address
    IERC20 public immutable usdc;
    
    /// @notice Price per node in USDC (6 decimals)
    uint256 public price = 1000 * 10**6;
    
    /// @notice Maximum number of nodes a single address can purchase
    uint256 public maxNodes = 25;
    
    /// @notice Total number of nodes sold
    uint256 public supply;
    
    /// @notice Flag indicating if sales are currently active
    bool public salesActive = false;
    
    /// @notice Flag indicating if whitelist functionality is enabled
    bool public isWhitelistEnabled = true;

    /// @notice List of all addresses that have purchased nodes
    address[] public buyers;

    /// @notice Mapping of addresses to their whitelist status
    mapping(address => bool) public whitelist;
    
    /// @notice Mapping of addresses to number of nodes purchased
    mapping(address => uint256) public nodesPurchased;

    /// @notice Emitted when a node is purchased
    /// @param buyer Address of the buyer
    /// @param amount Number of nodes purchased
    event NodePurchased(address buyer, uint256 amount);
    
    /// @notice Emitted when an address is added to whitelist
    /// @param user Address added to whitelist
    event WhitelistAdded(address user);
    
    /// @notice Emitted when an address is removed from whitelist
    /// @param user Address removed from whitelist
    event WhitelistRemoved(address user);
    
    /// @notice Emitted when the node price is updated
    /// @param newPrice New price per node
    event PriceUpdated(uint256 newPrice);
    
    /// @notice Emitted when sales status is changed
    /// @param isActive New sales status
    event SalesStatusChanged(bool isActive);
    
    /// @notice Emitted when whitelist status is changed
    /// @param isEnabled New whitelist status
    event WhitelistStatusChanged(bool isEnabled);
    
    /// @notice Emitted when maximum nodes per address is updated
    /// @param newMaxNodes New maximum nodes limit
    event MaxNodesUpdated(uint256 newMaxNodes);

    /// @notice Custom errors
    error InvalidUSDCAddress();
    error SalesNotActive();
    error NotWhitelisted();
    error ExceedsMaxNodes();
    error InsufficientUSDCAllowance();
    error InsufficientUSDCBalance();

    /// @notice Constructor initializes the contract with the deployer as owner and sets USDC address
    /// @param usdcAddress Address of the USDC token contract
    constructor(address usdcAddress) Ownable(msg.sender) {
        if (usdcAddress == address(0)) revert InvalidUSDCAddress();
        usdc = IERC20(usdcAddress);
    }

    /// @notice Purchase nodes using USDC
    /// @dev Checks for whitelist if enabled, verifies USDC allowance and balance
    /// @param nodeAmount Number of nodes to purchase
    function buy(uint256 nodeAmount) external nonReentrant {
        if (!salesActive) revert SalesNotActive();
        if (isWhitelistEnabled && !whitelist[msg.sender]) revert NotWhitelisted();
        if (nodesPurchased[msg.sender] + nodeAmount > maxNodes) revert ExceedsMaxNodes();
        
        uint256 totalPrice = price * nodeAmount;
        if (usdc.allowance(msg.sender, address(this)) < totalPrice) revert InsufficientUSDCAllowance();
        if (usdc.balanceOf(msg.sender) < totalPrice) revert InsufficientUSDCBalance();
        
        usdc.safeTransferFrom(msg.sender, address(this), totalPrice);
        
        if (nodesPurchased[msg.sender] == 0) {
            buyers.push(msg.sender);
        }
        nodesPurchased[msg.sender] += nodeAmount;
        supply += nodeAmount;
        emit NodePurchased(msg.sender, nodeAmount);
    }

    /// @notice Enable or disable whitelist functionality
    /// @dev Only callable by owner
    /// @param enabled New whitelist status
    function setWhitelistEnabled(bool enabled) external onlyOwner {
        isWhitelistEnabled = enabled;
        emit WhitelistStatusChanged(enabled);
    }
    
    /// @notice Update the price per node
    /// @dev Only callable by owner
    /// @param newPrice New price per node in USDC (6 decimals)
    function setNodePrice(uint256 newPrice) external onlyOwner {
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
    
    /// @notice Stop node sales
    /// @dev Only callable by owner
    function stopNodeSales() external onlyOwner {
        salesActive = false;
        emit SalesStatusChanged(false);
    }
    
    /// @notice Start node sales
    /// @dev Only callable by owner
    function startNodeSales() external onlyOwner {
        salesActive = true;
        emit SalesStatusChanged(true);
    }

    /// @notice Update maximum nodes per address
    /// @dev Only callable by owner
    /// @param newMaxNodes New maximum nodes limit
    function setMaxNodesPerAddress(uint256 newMaxNodes) external onlyOwner {
        maxNodes = newMaxNodes;
        emit MaxNodesUpdated(newMaxNodes);
    }

    /// @notice Withdraw all collected USDC to treasury
    /// @dev Only callable by owner
    function withdrawToTreasury() external onlyOwner {
        uint256 balance = usdc.balanceOf(address(this));
        if (balance > 0) {
            usdc.safeTransfer(TREASURY, balance);
        }
    }

    /// @notice Get list of all buyers and their node counts
    /// @return Array of buyer addresses
    /// @return Array of corresponding node counts
    function getAllBuyers() external view returns (address[] memory, uint256[] memory) {
        uint256[] memory counts = new uint256[](buyers.length);
        for (uint i; i < buyers.length; i++) {
            counts[i] = nodesPurchased[buyers[i]];
        }
        return (buyers, counts);
    }
}