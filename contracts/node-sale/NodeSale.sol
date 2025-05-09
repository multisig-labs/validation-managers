// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.8.29;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title NodeSale
/// @notice Contract for managing the sale of nodes with support for multiple ERC20 tokens
/// @dev Implements whitelist functionality and supports multiple payment tokens
contract NodeSale is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    
    /// @notice Treasury address where collected funds are sent
    address constant TREASURY = 0x1E3D04c315eDBb584A9fB85F5Aa30d6385a6859C;
    
    /// @notice Price per node in wei (18 decimals)
    uint256 public price = 1000 * 10**18;
    
    /// @notice Maximum number of nodes a single address can purchase
    uint256 public maxNodes = 25;
    
    /// @notice Total number of nodes sold
    uint256 public supply;
    
    /// @notice Flag indicating if sales are currently active
    bool public salesActive = false;
    
    /// @notice Flag indicating if whitelist functionality is enabled
    bool public isWhitelistEnabled = true;

    /// @notice List of all supported payment tokens
    address[] private supportedTokenList;
    
    /// @notice List of all addresses that have purchased nodes
    address[] public buyers;

    /// @notice Mapping of addresses to their whitelist status
    mapping(address => bool) public whitelist;
    
    /// @notice Mapping of addresses to number of nodes purchased
    mapping(address => uint256) public nodesPurchased;
    
    /// @notice Mapping of token addresses to their support status
    mapping(address => bool) public supportedTokens;

    /// @notice Emitted when a node is purchased
    /// @param buyer Address of the buyer
    /// @param token Address of the token used for payment
    /// @param amount Number of nodes purchased
    event NodePurchased(address buyer, address token, uint256 amount);
    
    /// @notice Emitted when an address is added to whitelist
    /// @param user Address added to whitelist
    event WhitelistAdded(address user);
    
    /// @notice Emitted when an address is removed from whitelist
    /// @param user Address removed from whitelist
    event WhitelistRemoved(address user);
    
    /// @notice Emitted when a new token is added as payment option
    /// @param token Address of the added token
    event TokenAdded(address token);
    
    /// @notice Emitted when a token is removed as payment option
    /// @param token Address of the removed token
    event TokenRemoved(address token);
    
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

    /// @notice Constructor initializes the contract with the deployer as owner
    constructor() Ownable(msg.sender) {}

    /// @notice Purchase nodes using supported ERC20 tokens
    /// @dev Checks for whitelist if enabled, verifies token allowance and balance
    /// @param nodeAmount Number of nodes to purchase
    function buy(uint256 nodeAmount) external nonReentrant {
        require(salesActive, "Sales are not active");
        if (isWhitelistEnabled) {
            require(whitelist[msg.sender], "Not whitelisted");
        }
        address selectedToken = address(0);
        uint256 requiredAmount = 0;
        
        for (uint i; i < supportedTokenList.length; i++) {
            address token = supportedTokenList[i];
            if (!supportedTokens[token]) continue;
            
            IERC20 tokenContract = IERC20(token);
            
            uint8 decimals;
            (bool success, bytes memory data) = token.staticcall(abi.encodeWithSignature("decimals()"));
            if (success && data.length >= 32) {
                decimals = uint8(abi.decode(data, (uint8)));
            } else {
                decimals = 18;
            }
            
            uint256 tokenPrice = price * 10**decimals / 10**18;
            uint256 totalPrice = tokenPrice * nodeAmount;
            
            uint256 allowance = tokenContract.allowance(msg.sender, address(this));
            uint256 balanceOf = tokenContract.balanceOf(msg.sender);
            if ((allowance >= totalPrice) && (balanceOf >= totalPrice)) {
                selectedToken = token;
                requiredAmount = totalPrice;
                break;
            }
        }
        
        require(selectedToken != address(0), "No token with sufficient allowance");
        IERC20(selectedToken).safeTransferFrom(msg.sender, address(this), requiredAmount);
        
        if (nodesPurchased[msg.sender] == 0) {
            buyers.push(msg.sender);
        }
        nodesPurchased[msg.sender] += nodeAmount;
        supply += nodeAmount;
        require(nodesPurchased[msg.sender] <= maxNodes, "You can't buy more nodes");
        emit NodePurchased(msg.sender, selectedToken, nodeAmount);
    }
    
    /// @notice Add a new supported payment token
    /// @dev Only callable by owner
    /// @param token Address of the token to add
    function addSupportedToken(address token) external onlyOwner {
        if (!supportedTokens[token]) {
            supportedTokens[token] = true;
            supportedTokenList.push(token);
            emit TokenAdded(token);
        }
    }

    /// @notice Remove a supported payment token
    /// @dev Only callable by owner
    /// @param token Address of the token to remove
    function removeSupportedToken(address token) external onlyOwner {
        if (supportedTokens[token]) {
            supportedTokens[token] = false;
            for (uint i; i < supportedTokenList.length; i++) {
                if (supportedTokenList[i] == token) {
                    if (i < supportedTokenList.length - 1) {
                        supportedTokenList[i] = supportedTokenList[supportedTokenList.length - 1];
                    }
                    supportedTokenList.pop();
                    break;
                }
            }            
            emit TokenRemoved(token);
        }
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
    /// @param newPrice New price per node in wei
    function setPrice(uint256 newPrice) external onlyOwner {
        price = newPrice;
        emit PriceUpdated(newPrice);
    }
    
    /// @notice Add an address to the whitelist
    /// @dev Only callable by owner
    /// @param user Address to add to whitelist
    function addWhitelist(address user) external onlyOwner {
        whitelist[user] = true;
        emit WhitelistAdded(user);
    }
    
    /// @notice Remove an address from the whitelist
    /// @dev Only callable by owner
    /// @param user Address to remove from whitelist
    function removeWhitelist(address user) external onlyOwner {
        whitelist[user] = false;
        emit WhitelistRemoved(user);
    }
    
    /// @notice Stop node sales
    /// @dev Only callable by owner
    function stop() external onlyOwner {
        salesActive = false;
        emit SalesStatusChanged(false);
    }
    
    /// @notice Start node sales
    /// @dev Only callable by owner
    function start() external onlyOwner {
        salesActive = true;
        emit SalesStatusChanged(true);
    }

    /// @notice Update maximum nodes per address
    /// @dev Only callable by owner
    /// @param newMaxNodes New maximum nodes limit
    function setMaxNodes(uint256 newMaxNodes) external onlyOwner {
        maxNodes = newMaxNodes;
        emit MaxNodesUpdated(newMaxNodes);
    }

    /// @notice Withdraw all collected tokens to treasury
    /// @dev Only callable by owner
    function withdraw() external onlyOwner {
        for (uint i; i < supportedTokenList.length; i++) {
            address token = supportedTokenList[i];
            if (supportedTokens[token]) {
                uint256 balance = IERC20(token).balanceOf(address(this));
                if (balance > 0) {
                    IERC20(token).safeTransfer(TREASURY, balance);
                }
            }
        }
    }

    /// @notice Get list of all supported payment tokens
    /// @return Array of supported token addresses
    function getSupportedTokens() external view returns (address[] memory) {
        return supportedTokenList;
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