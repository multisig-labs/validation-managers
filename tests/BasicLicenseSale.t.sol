// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

import { Test } from "forge-std-1.9.6/src/Test.sol";
import { BasicLicenseSale } from "../contracts/license-sale/BasicLicenseSale.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Base } from "./utils/Base.sol";

contract MockERC20 is IERC20 {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint8 private _decimals = 6;

    function mint(address to, uint256 amount) external {
        _balances[to] += amount;
    }

    function totalSupply() external pure returns (uint256) {
        return 0;
    }

    function decimals() external view returns (uint8) {
        return _decimals;
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

contract BasicLicenseSaleTest is Base {
    BasicLicenseSale public licenseSale;
    MockERC20 public usdc;
    address public treasury;
    address public buyer;
    address public nonWhitelistedBuyer;

    event LicensePurchased(address buyer, uint256 amount, uint256 totalCost);

    function setUp() public override {
        super.setUp();
        
        // Deploy mock USDC
        usdc = new MockERC20();
        
        // Setup treasury
        treasury = getNamedActor("treasury");
        
        // Deploy BasicLicenseSale
        licenseSale = new BasicLicenseSale(address(usdc), treasury);
        
        // Setup actors
        buyer = getNamedActor("buyer");
        nonWhitelistedBuyer = getNamedActor("nonWhitelistedBuyer");
        
        // Mint USDC to buyers
        usdc.mint(buyer, 1000000 * 10**6); // 1M USDC
        usdc.mint(nonWhitelistedBuyer, 1000000 * 10**6); // 1M USDC
        
        // Start sales and whitelist buyer
        vm.startPrank(licenseSale.owner());
        licenseSale.startLicenseSales();
        licenseSale.addToWhitelist(buyer);
        vm.stopPrank();
    }

    function test_InitialState() public {
        assertEq(address(licenseSale.usdc()), address(usdc));
        assertEq(licenseSale.treasury(), treasury);
        assertEq(licenseSale.price(), 10_000); // 0.01 USDC
        assertEq(licenseSale.maxLicenses(), 250);
        assertEq(licenseSale.maxTotalSupply(), 1000);
        assertEq(licenseSale.supply(), 0);
        assertTrue(licenseSale.salesActive());
        assertFalse(licenseSale.isWhitelistEnabled());
    }

    function test_BuyLicense() public {
        // Setup
        vm.startPrank(buyer);
        usdc.approve(address(licenseSale), 10_000);
        
        // Buy license
        vm.expectEmit(true, true, true, true);
        emit LicensePurchased(buyer, 1, 10_000);
        licenseSale.buy(1);
        
        // Verify
        assertEq(licenseSale.licensesPurchased(buyer), 1);
        assertEq(licenseSale.supply(), 1);
        assertEq(usdc.balanceOf(address(licenseSale)), 10_000);
        vm.stopPrank();
    }

    function test_BuyLicenseWithoutWhitelist() public {
        // Setup
        vm.startPrank(nonWhitelistedBuyer);
        usdc.approve(address(licenseSale), 10_000);
        
        // Should succeed since whitelist is disabled by default
        vm.expectEmit(true, true, true, true);
        emit LicensePurchased(nonWhitelistedBuyer, 1, 10_000);
        licenseSale.buy(1);
        
        // Enable whitelist
        vm.stopPrank();
        vm.startPrank(licenseSale.owner());
        licenseSale.setWhitelistEnabled(true);
        
        // Should fail now
        vm.stopPrank();
        vm.startPrank(nonWhitelistedBuyer);
        vm.expectRevert(BasicLicenseSale.NotWhitelisted.selector);
        licenseSale.buy(1);
        
        vm.stopPrank();
    }

    function test_BuyMaxLicenses() public {
        // Setup
        vm.startPrank(buyer);
        usdc.approve(address(licenseSale), 250 * 10_000);
        
        // Buy max licenses
        vm.expectEmit(true, true, true, true);
        emit LicensePurchased(buyer, 250, 250 * 10_000);
        licenseSale.buy(250);
        
        // Verify
        assertEq(licenseSale.licensesPurchased(buyer), 250);
        assertEq(licenseSale.supply(), 250);
        
        // Try to buy more
        vm.expectRevert(BasicLicenseSale.ExceedsMaxLicenses.selector);
        licenseSale.buy(1);
        
        vm.stopPrank();
    }

    function test_Withdraw() public {
        // Setup
        vm.startPrank(buyer);
        usdc.approve(address(licenseSale), 10_000);
        vm.expectEmit(true, true, true, true);
        emit LicensePurchased(buyer, 1, 10_000);
        licenseSale.buy(1);
        vm.stopPrank();
        
        // Withdraw
        vm.prank(licenseSale.owner());
        licenseSale.withdrawToTreasury();
        
        // Verify
        assertEq(usdc.balanceOf(address(licenseSale)), 0);
        assertEq(usdc.balanceOf(treasury), 10_000);
    }

    function test_UpdatePrice() public {
        // Setup
        vm.prank(licenseSale.owner());
        licenseSale.setLicensePrice(20_000);
        
        // Verify
        assertEq(licenseSale.price(), 20_000);
        
        // Buy with new price
        vm.startPrank(buyer);
        usdc.approve(address(licenseSale), 20_000);
        vm.expectEmit(true, true, true, true);
        emit LicensePurchased(buyer, 1, 20_000);
        licenseSale.buy(1);
        
        // Verify
        assertEq(usdc.balanceOf(address(licenseSale)), 20_000);
        vm.stopPrank();
    }

    function test_UpdateMaxLicenses() public {
        // Setup
        vm.prank(licenseSale.owner());
        licenseSale.setMaxLicensesPerAddress(50);
        
        // Verify
        assertEq(licenseSale.maxLicenses(), 50);
        
        // Buy more licenses
        vm.startPrank(buyer);
        usdc.approve(address(licenseSale), 50 * 10_000);
        vm.expectEmit(true, true, true, true);
        emit LicensePurchased(buyer, 50, 50 * 10_000);
        licenseSale.buy(50);
        
        // Verify
        assertEq(licenseSale.licensesPurchased(buyer), 50);
        assertEq(licenseSale.supply(), 50);
        vm.stopPrank();
    }

    function test_WhitelistManagement() public {
        // Add to whitelist
        vm.prank(licenseSale.owner());
        licenseSale.addToWhitelist(buyer);
        assertTrue(licenseSale.whitelist(buyer));
        
        // Remove from whitelist
        vm.prank(licenseSale.owner());
        licenseSale.removeFromWhitelist(buyer);
        assertFalse(licenseSale.whitelist(buyer));
    }

    function test_SalesStatus() public {
        // Stop sales
        vm.prank(licenseSale.owner());
        licenseSale.stopLicenseSales();
        assertFalse(licenseSale.salesActive());
        
        // Try to buy
        vm.startPrank(buyer);
        usdc.approve(address(licenseSale), 10_000);
        vm.expectRevert(BasicLicenseSale.SalesNotActive.selector);
        licenseSale.buy(1);
        vm.stopPrank();
        
        // Start sales
        vm.prank(licenseSale.owner());
        licenseSale.startLicenseSales();
        assertTrue(licenseSale.salesActive());
        
        // Buy should work now
        vm.startPrank(buyer);
        licenseSale.buy(1);
        assertEq(licenseSale.licensesPurchased(buyer), 1);
        vm.stopPrank();
    }

    function test_UpdateMaxTotalSupply() public {
        // Setup
        vm.prank(licenseSale.owner());
        licenseSale.setMaxTotalSupply(2000);
        
        // Verify
        assertEq(licenseSale.maxTotalSupply(), 2000);
    }

    function test_ExceedsMaxTotalSupply() public {
        // Setup multiple buyers
        address[] memory testBuyers = new address[](5);
        for(uint i = 0; i < 5; i++) {
            testBuyers[i] = address(uint160(0x1000 + i));
            usdc.mint(testBuyers[i], 1000 * 10_000); // Give each buyer enough USDC
        }

        // Buy up to max total supply
        for(uint i = 0; i < 4; i++) {
            vm.startPrank(testBuyers[i]);
            usdc.approve(address(licenseSale), 250 * 10_000);
            licenseSale.buy(250); // Each buyer buys max licenses
            vm.stopPrank();
        }

        // Last buyer tries to buy more than remaining supply
        vm.startPrank(testBuyers[4]);
        usdc.approve(address(licenseSale), 250 * 10_000);
        vm.expectRevert(BasicLicenseSale.ExceedsMaxTotalSupply.selector);
        licenseSale.buy(250); // This would exceed max total supply
        vm.stopPrank();

        // Verify total supply
        assertEq(licenseSale.supply(), 1000);
    }
} 