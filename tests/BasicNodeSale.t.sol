// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

import { Test } from "forge-std-1.9.6/src/Test.sol";
import { BasicNodeSale } from "../contracts/node-sale/BasicNodeSale.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Base } from "./utils/Base.sol";

contract MockERC20 is IERC20 {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint8 private _decimals = 6;

    function mint(address to, uint256 amount) external {
        _balances[to] += amount;
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    function totalSupply() external pure returns (uint256) {
        return 0;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _balances[msg.sender] -= amount;
        _balances[to] += amount;
        return true;
    }

    function allowance(address owner, address spender) external view returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        _allowances[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        _allowances[from][msg.sender] -= amount;
        _balances[from] -= amount;
        _balances[to] += amount;
        return true;
    }
}

contract BasicNodeSaleTest is Base {
    BasicNodeSale public nodeSale;
    MockERC20 public usdc;
    address constant TREASURY = 0x1E3D04c315eDBb584A9fB85F5Aa30d6385a6859C;
    address public buyer;
    address public nonWhitelistedBuyer;

    function setUp() public override {
        super.setUp();
        
        // Deploy mock USDC
        usdc = new MockERC20();
        
        // Deploy BasicNodeSale
        nodeSale = new BasicNodeSale(address(usdc));
        
        // Setup actors
        buyer = getNamedActor("buyer");
        nonWhitelistedBuyer = getNamedActor("nonWhitelistedBuyer");
        
        // Mint USDC to buyers
        usdc.mint(buyer, 1000000 * 10**6); // 1M USDC
        usdc.mint(nonWhitelistedBuyer, 1000000 * 10**6); // 1M USDC
        
        // Start sales and whitelist buyer
        vm.startPrank(nodeSale.owner());
        nodeSale.startNodeSales();
        nodeSale.addToWhitelist(buyer);
        vm.stopPrank();
    }

    function test_InitialState() public {
        assertEq(address(nodeSale.usdc()), address(usdc));
        assertEq(nodeSale.price(), 1000 * 10**6);
        assertEq(nodeSale.maxNodes(), 25);
        assertEq(nodeSale.supply(), 0);
        assertTrue(nodeSale.salesActive());
        assertTrue(nodeSale.isWhitelistEnabled());
    }

    function test_BuyNode() public {
        // Setup
        vm.startPrank(buyer);
        usdc.approve(address(nodeSale), 1000 * 10**6);
        
        // Buy node
        nodeSale.buy(1);
        
        // Verify
        assertEq(nodeSale.nodesPurchased(buyer), 1);
        assertEq(nodeSale.supply(), 1);
        assertEq(usdc.balanceOf(address(nodeSale)), 1000 * 10**6);
        vm.stopPrank();
    }

    function test_BuyNodeWithoutWhitelist() public {
        // Setup
        vm.startPrank(nonWhitelistedBuyer);
        usdc.approve(address(nodeSale), 1000 * 10**6);
        
        // Should fail without whitelist
        vm.expectRevert(BasicNodeSale.NotWhitelisted.selector);
        nodeSale.buy(1);
        
        // Disable whitelist
        vm.stopPrank();
        vm.prank(nodeSale.owner());
        nodeSale.setWhitelistEnabled(false);
        
        // Should succeed now
        vm.startPrank(nonWhitelistedBuyer);
        nodeSale.buy(1);
        
        // Verify
        assertEq(nodeSale.nodesPurchased(nonWhitelistedBuyer), 1);
        assertEq(nodeSale.supply(), 1);
        vm.stopPrank();
    }

    function test_BuyMaxNodes() public {
        // Setup
        vm.startPrank(buyer);
        usdc.approve(address(nodeSale), 25000 * 10**6);
        
        // Buy max nodes
        nodeSale.buy(25);
        
        // Verify
        assertEq(nodeSale.nodesPurchased(buyer), 25);
        assertEq(nodeSale.supply(), 25);
        
        // Try to buy more
        vm.expectRevert(BasicNodeSale.ExceedsMaxNodes.selector);
        nodeSale.buy(1);
        
        vm.stopPrank();
    }

    function test_Withdraw() public {
        // Setup
        vm.startPrank(buyer);
        usdc.approve(address(nodeSale), 1000 * 10**6);
        nodeSale.buy(1);
        vm.stopPrank();
        
        // Withdraw
        vm.prank(nodeSale.owner());
        nodeSale.withdrawToTreasury();
        
        // Verify
        assertEq(usdc.balanceOf(address(nodeSale)), 0);
        assertEq(usdc.balanceOf(TREASURY), 1000 * 10**6);
    }

    function test_UpdatePrice() public {
        // Setup
        vm.prank(nodeSale.owner());
        nodeSale.setNodePrice(2000 * 10**6);
        
        // Verify
        assertEq(nodeSale.price(), 2000 * 10**6);
        
        // Buy with new price
        vm.startPrank(buyer);
        usdc.approve(address(nodeSale), 2000 * 10**6);
        nodeSale.buy(1);
        
        // Verify
        assertEq(usdc.balanceOf(address(nodeSale)), 2000 * 10**6);
        vm.stopPrank();
    }

    function test_UpdateMaxNodes() public {
        // Setup
        vm.prank(nodeSale.owner());
        nodeSale.setMaxNodesPerAddress(50);
        
        // Verify
        assertEq(nodeSale.maxNodes(), 50);
        
        // Buy more nodes
        vm.startPrank(buyer);
        usdc.approve(address(nodeSale), 50000 * 10**6);
        nodeSale.buy(50);
        
        // Verify
        assertEq(nodeSale.nodesPurchased(buyer), 50);
        assertEq(nodeSale.supply(), 50);
        vm.stopPrank();
    }

    function test_WhitelistManagement() public {
        // Add to whitelist
        vm.prank(nodeSale.owner());
        nodeSale.addToWhitelist(buyer);
        assertTrue(nodeSale.whitelist(buyer));
        
        // Remove from whitelist
        vm.prank(nodeSale.owner());
        nodeSale.removeFromWhitelist(buyer);
        assertFalse(nodeSale.whitelist(buyer));
    }

    function test_SalesStatus() public {
        // Stop sales
        vm.prank(nodeSale.owner());
        nodeSale.stopNodeSales();
        assertFalse(nodeSale.salesActive());
        
        // Try to buy
        vm.startPrank(buyer);
        usdc.approve(address(nodeSale), 1000 * 10**6);
        vm.expectRevert(BasicNodeSale.SalesNotActive.selector);
        nodeSale.buy(1);
        vm.stopPrank();
        
        // Start sales
        vm.prank(nodeSale.owner());
        nodeSale.startNodeSales();
        assertTrue(nodeSale.salesActive());
        
        // Buy should work now
        vm.startPrank(buyer);
        nodeSale.buy(1);
        assertEq(nodeSale.nodesPurchased(buyer), 1);
        vm.stopPrank();
    }
} 