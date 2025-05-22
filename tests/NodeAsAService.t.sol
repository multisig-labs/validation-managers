// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

/**
 * @title NodeAsAServiceTest
 * @notice Test suite for the NodeAsAService contract
 * @dev Tests the functionality of node service payments and administrative functions
 */
import { NodeAsAService, PaymentRecord } from "../contracts/NodeAsAService.sol";
import { MockERC20 } from "./mocks/MockERC20.sol";
import { ERC1967Proxy } from "../dependencies/@openzeppelin-contracts-5.3.0/proxy/ERC1967/ERC1967Proxy.sol";
import { Base } from "./utils/Base.sol";
import { IAccessControl } from "../dependencies/@openzeppelin-contracts-5.3.0/access/IAccessControl.sol";

contract NodeAsAServiceTest is Base {
    NodeAsAService public nodeAsAService;
    MockERC20 public usdc;
    
    address public admin;
    address public protocolManager;
    address public user1;
    address public user2;
    address public treasury;
    
    uint256 public constant INITIAL_PRICE = 100 * 1e6; // 100 USDC per month (6 decimals)
    uint256 public constant INITIAL_BALANCE = 1000 * 1e6; // 1000 USDC
    
    bytes32 public constant PROTOCOL_MANAGER_ROLE = keccak256("PROTOCOL_MANAGER_ROLE");
    
    /**
     * @notice Sets up the test environment
     * @dev Deploys mock contracts, initializes NodeAsAService, and sets up test accounts
     */
    function setUp() public override {
        super.setUp();
        
        // Setup actors
        admin = makeAddr("admin");
        protocolManager = makeAddr("protocolManager");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        treasury = makeAddr("treasury");
        
        // Deploy mock USDC
        usdc = new MockERC20("USD Coin", "USDC", 6);
        
        // Deploy NodeAsAService
        NodeAsAService implementation = new NodeAsAService();
        
        bytes memory data = abi.encodeWithSelector(
            NodeAsAService.initialize.selector,
            address(usdc),
            admin,
            INITIAL_PRICE,
            treasury
        );
        nodeAsAService = NodeAsAService(address(new ERC1967Proxy(address(implementation), data)));
        
        // Setup roles
        vm.prank(admin);
        nodeAsAService.grantRole(PROTOCOL_MANAGER_ROLE, protocolManager);
        
        // Fund users with USDC
        // Mint enough USDC for 70 licenses for 6 months (42,000 USDC)
        uint256 largeBalance = 100_000 * 1e6; // 100,000 USDC
        usdc.mint(user1, largeBalance);
        usdc.mint(user2, largeBalance);
    }
    
    /**
     * @notice Tests the initialization of the NodeAsAService contract
     * @dev Verifies that all contract parameters are set correctly during initialization
     */
    function test_Initialization() public view {
        assertEq(address(nodeAsAService.usdc()), address(usdc));
        assertEq(nodeAsAService.licensePricePerMonth(), INITIAL_PRICE);
        assertTrue(nodeAsAService.hasRole(nodeAsAService.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(nodeAsAService.hasRole(PROTOCOL_MANAGER_ROLE, protocolManager));
        assertEq(nodeAsAService.treasury(), treasury);
    }
    
    /**
     * @notice Tests the payment for node services functionality
     * @dev Verifies that users can pay for node services and payment records are created correctly
     */
    function test_PayForNodeServices() public {
        uint8 licenseCount = 70;
        uint8 durationInMonths = 6;
        bytes32 subnetId = bytes32("test-subnet");
        
        // Approve USDC spending
        vm.prank(user1);
        usdc.approve(address(nodeAsAService), type(uint256).max);
        
        // Calculate expected payment
        uint256 expectedPayment = INITIAL_PRICE * licenseCount * durationInMonths;
        
        // Pay for services
        vm.prank(user1);
        nodeAsAService.payForNodeServices(licenseCount, durationInMonths, subnetId);
        
        // Verify payment record
        PaymentRecord memory record = nodeAsAService.getPaymentRecord(1);
        assertEq(record.buyer, user1);
        assertEq(record.licenseCount, licenseCount);
        assertEq(record.subnetId, subnetId);
        assertEq(record.durationInMonths, durationInMonths);
        assertEq(record.totalAmountPaidInUSDC, expectedPayment);
        assertEq(record.pricePerMonthInUSDC, INITIAL_PRICE);
    }
    
    /**
     * @notice Tests that payment for node services reverts with zero license count
     * @dev Verifies the MustPayForAtLeastOneLicense error is thrown
     */
    function test_RevertWhen_PayForNodeServices_ZeroLicenseCount() public {
        vm.prank(user1);
        vm.expectRevert(NodeAsAService.MustPayForAtLeastOneLicense.selector);
        nodeAsAService.payForNodeServices(0, 1, bytes32("test-subnet"));
    }
    
    /**
     * @notice Tests that payment for node services reverts with zero duration
     * @dev Verifies the DurationMustBeGreaterThanZero error is thrown
     */
    function test_RevertWhen_PayForNodeServices_ZeroDuration() public {
        vm.prank(user1);
        vm.expectRevert(NodeAsAService.DurationMustBeGreaterThanZero.selector);
        nodeAsAService.payForNodeServices(1, 0, bytes32("test-subnet"));
    }

    /**
     * @notice Tests that payment for node services reverts with insufficient balance
     * @dev Verifies the InsufficientBalance error is thrown when user has insufficient USDC
     */
    function test_RevertWhen_PayForNodeServices_InsufficientBalance() public {
        // Create a user with no USDC balance
        address poorUser = makeAddr("poorUser");
        
        // Try to pay for services
        vm.prank(poorUser);
        vm.expectRevert(NodeAsAService.InsufficientBalance.selector);
        nodeAsAService.payForNodeServices(1, 1, bytes32("test-subnet"));
    }

    /**
     * @notice Tests that payment for node services reverts with transfer failure
     * @dev Verifies that the SafeERC20 error is thrown when USDC transfer fails
     */
    function test_RevertWhen_PayForNodeServices_TransferFailed() public {
        // First approve spending
        vm.startPrank(user1);
        usdc.approve(address(nodeAsAService), type(uint256).max);
        vm.stopPrank();

        // Set transfer to fail
        usdc.setTransferShouldFail(true);

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(
            bytes4(keccak256("SafeERC20FailedOperation(address)")),
            address(usdc)
        ));
        nodeAsAService.payForNodeServices(1, 1, bytes32("test-subnet"));
    }

    /**
     * @notice Tests the fund withdrawal functionality
     * @dev Verifies that protocol managers can withdraw funds from the contract
     */
    function test_WithdrawFunds() public {
        // First create a payment to add funds to the contract
        vm.startPrank(user1);
        usdc.approve(address(nodeAsAService), type(uint256).max);
        nodeAsAService.payForNodeServices(1, 1, bytes32("test-subnet"));
        vm.stopPrank();
        
        uint256 contractBalance = usdc.balanceOf(address(nodeAsAService));
        uint256 treasuryBalance = usdc.balanceOf(treasury);
        
        // Withdraw funds
        vm.prank(protocolManager);
        nodeAsAService.withdrawFunds(contractBalance);
        
        // Verify withdrawal went to treasury
        assertEq(usdc.balanceOf(address(nodeAsAService)), 0);
        assertEq(usdc.balanceOf(treasury), treasuryBalance + contractBalance);
    }
    
    /**
     * @notice Tests the license price update functionality
     * @dev Verifies that admins can update the license price per month
     */
    function test_UpdateLicensePrice() public {
        uint32 newPrice = 200 * 1e6; // 200 USDC per month
        vm.prank(protocolManager);
        nodeAsAService.setLicensePricePerMonth(newPrice);
        assertEq(nodeAsAService.licensePricePerMonth(), newPrice);
    }

    /**
     * @notice Tests that withdrawal reverts with zero amount
     * @dev Verifies the AmountMustBeGreaterThanZero error is thrown
     */
    function test_RevertWhen_WithdrawFunds_ZeroAmount() public {
        vm.prank(protocolManager);
        vm.expectRevert(NodeAsAService.AmountMustBeGreaterThanZero.selector);
        nodeAsAService.withdrawFunds(0);
    }

    /**
     * @notice Tests that withdrawal reverts with insufficient contract balance
     * @dev Verifies the InsufficientContractBalance error is thrown
     */
    function test_RevertWhen_WithdrawFunds_InsufficientBalance() public {
        vm.prank(protocolManager);
        vm.expectRevert(NodeAsAService.InsufficientContractBalance.selector);
        nodeAsAService.withdrawFunds(1); // Try to withdraw when contract has no balance
    }

    /**
     * @notice Tests that protocol manager can update license price
     */
    function test_ProtocolManagerCanUpdatePrice() public {
        uint32 newPrice = 300 * 1e6; // 300 USDC per month
        vm.prank(protocolManager);
        nodeAsAService.setLicensePricePerMonth(newPrice);
        assertEq(nodeAsAService.licensePricePerMonth(), newPrice);
    }

    /**
     * @notice Tests that admin cannot update license price
     */
    function test_RevertWhen_AdminCannotUpdatePrice() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(
            IAccessControl.AccessControlUnauthorizedAccount.selector,
            admin,
            PROTOCOL_MANAGER_ROLE
        ));
        nodeAsAService.setLicensePricePerMonth(400 * 1e6);
    }

    /**
     * @notice Tests that non-admin and non-protocol manager cannot update license price
     */
    function test_RevertWhen_NonAdminOrProtocolManagerCannotUpdatePrice() public {
        address notAllowed = makeAddr("notAllowed");
        vm.prank(notAllowed);
        vm.expectRevert(abi.encodeWithSelector(
            IAccessControl.AccessControlUnauthorizedAccount.selector,
            notAllowed,
            PROTOCOL_MANAGER_ROLE
        ));
        nodeAsAService.setLicensePricePerMonth(400 * 1e6);
    }

    /**
     * @notice Tests that protocol manager cannot set zero price
     */
    function test_RevertWhen_ProtocolManagerUpdatePrice_ZeroPrice() public {
        vm.prank(protocolManager);
        vm.expectRevert(NodeAsAService.InvalidPrice.selector);
        nodeAsAService.setLicensePricePerMonth(0);
    }

    /**
     * @notice Tests that admin cannot withdraw funds
     */
    function test_RevertWhen_AdminCannotWithdrawFunds() public {
        // First create a payment to add funds to the contract
        vm.startPrank(user1);
        usdc.approve(address(nodeAsAService), type(uint256).max);
        nodeAsAService.payForNodeServices(1, 1, bytes32("test-subnet"));
        vm.stopPrank();
        
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(
            IAccessControl.AccessControlUnauthorizedAccount.selector,
            admin,
            PROTOCOL_MANAGER_ROLE
        ));
        nodeAsAService.withdrawFunds(100);
    }

    /**
     * @notice Tests that admin cannot pause contract
     */
    function test_RevertWhen_AdminCannotPauseContract() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(
            IAccessControl.AccessControlUnauthorizedAccount.selector,
            admin,
            PROTOCOL_MANAGER_ROLE
        ));
        nodeAsAService.setPaused(true);
    }
} 
