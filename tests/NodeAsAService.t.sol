// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

/**
 * @title NodeAsAServiceTest
 * @notice Test suite for the NodeAsAService contract
 * @dev Tests the functionality of node service payments, token assignments, and administrative functions
 */
import { NodeAsAService } from "../contracts/NodeAsAService.sol";
import { ERC721Mock } from "./mocks/ERC721Mock.sol";
import { MockERC20 } from "./mocks/MockERC20.sol";
import { ERC1967Proxy } from "../dependencies/@openzeppelin-contracts-5.3.0/proxy/ERC1967/ERC1967Proxy.sol";
import { Base } from "./utils/Base.sol";
import { IAccessControl } from "../dependencies/@openzeppelin-contracts-5.3.0/access/IAccessControl.sol";

contract NodeAsAServiceTest is Base {
    NodeAsAService public nodeAsAService;
    ERC721Mock public nodeLicense;
    MockERC20 public usdc;
    
    address public admin;
    address public scribe;
    address public protocolManager;
    address public user1;
    address public user2;
    
    uint256 public constant INITIAL_PRICE = 100 * 1e6; // 100 USDC (6 decimals)
    uint256 public constant INITIAL_BALANCE = 1000 * 1e6; // 1000 USDC
    
    bytes32 public constant SCRIBE_ROLE = keccak256("SCRIBE_ROLE");
    bytes32 public constant PROTOCOL_MANAGER_ROLE = keccak256("PROTOCOL_MANAGER_ROLE");
    
    /**
     * @notice Sets up the test environment
     * @dev Deploys mock contracts, initializes NodeAsAService, and sets up test accounts
     */
    function setUp() public override {
        super.setUp();
        
        // Setup actors
        admin = makeAddr("admin");
        scribe = makeAddr("scribe");
        protocolManager = makeAddr("protocolManager");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        
        // Deploy mock USDC
        usdc = new MockERC20("USD Coin", "USDC", 6);
        
        // Deploy mock NodeLicense
        nodeLicense = new ERC721Mock("Node License", "NODE");
        
        // Deploy NodeAsAService
        NodeAsAService implementation = new NodeAsAService();
        bytes memory data = abi.encodeWithSelector(
            NodeAsAService.initialize.selector,
            address(usdc),
            address(nodeLicense),
            admin,
            scribe,
            INITIAL_PRICE
        );
        nodeAsAService = NodeAsAService(address(new ERC1967Proxy(address(implementation), data)));
        
        // Setup roles
        vm.prank(admin);
        nodeAsAService.setProtocolManager(protocolManager);
        
        // Fund users with USDC
        usdc.mint(user1, INITIAL_BALANCE);
        usdc.mint(user2, INITIAL_BALANCE);
    }
    
    /**
     * @notice Tests the initialization of the NodeAsAService contract
     * @dev Verifies that all contract parameters are set correctly during initialization
     */
    function test_Initialization() public {
        assertEq(address(nodeAsAService.usdc()), address(usdc));
        assertEq(address(nodeAsAService.nodeLicense()), address(nodeLicense));
        assertEq(nodeAsAService.licensePricePerMonth(), INITIAL_PRICE);
        assertTrue(nodeAsAService.hasRole(nodeAsAService.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(nodeAsAService.hasRole(nodeAsAService.SCRIBE_ROLE(), scribe));
        assertTrue(nodeAsAService.hasRole(nodeAsAService.PROTOCOL_MANAGER_ROLE(), protocolManager));
    }
    
    /**
     * @notice Tests the payment for node services functionality
     * @dev Verifies that users can pay for node services and payment records are created correctly
     */
    function test_PayForNodeServices() public {
        uint256 licenseCount = 2;
        uint256 duration = 30 days;
        bytes32 subnetId = bytes32("test-subnet");
        
        // Approve USDC spending
        vm.prank(user1);
        usdc.approve(address(nodeAsAService), type(uint256).max);
        
        // Calculate expected payment
        uint256 expectedPayment = nodeAsAService.calculateRequiredPayment(licenseCount, duration);
        
        // Pay for services
        vm.prank(user1);
        nodeAsAService.payForNodeServices(licenseCount, duration, subnetId);
        
        // Verify payment record
        NodeAsAService.PaymentRecord[] memory records = nodeAsAService.getUserPaymentRecords(user1);
        assertEq(records.length, 1);
        NodeAsAService.PaymentRecord memory record = records[0];
        assertEq(record.user, user1);
        assertEq(record.licenseCount, licenseCount);
        assertEq(record.subnetId, subnetId);
        assertEq(record.totalCumulativeDurationInSeconds, duration);
        assertEq(record.totalAmountPaidInUSDC, expectedPayment);
        assertEq(record.pricePerMonthAtPayment, INITIAL_PRICE);
    }
    
    /**
     * @notice Tests the token assignment functionality
     * @dev Verifies that scribes can assign node IDs to token IDs in payment records
     */
    function test_AddTokenAssignments() public {
        // First create a payment record
        vm.startPrank(user1);
        usdc.approve(address(nodeAsAService), type(uint256).max);
        nodeAsAService.payForNodeServices(2, 30 days, bytes32("test-subnet"));
        vm.stopPrank();
        
        // Mint some tokens
        uint256 tokenId1 = nodeLicense.mint(user1);
        uint256 tokenId2 = nodeLicense.mint(user1);
        
        // Add token assignments
        uint256[] memory tokenIds = new uint256[](2);
        bytes[] memory nodeIds = new bytes[](2);
        tokenIds[0] = tokenId1;
        tokenIds[1] = tokenId2;
        nodeIds[0] = "node1";
        nodeIds[1] = "node2";
        
        vm.prank(scribe);
        nodeAsAService.addTokenAssignments(user1, 0, tokenIds, nodeIds);
        
        // Verify assignments using getNodeIdForToken
        bytes memory nodeId1 = nodeAsAService.getNodeIdForToken(user1, 0, tokenId1);
        bytes memory nodeId2 = nodeAsAService.getNodeIdForToken(user1, 0, tokenId2);
        assertEq(string(nodeId1), "node1");
        assertEq(string(nodeId2), "node2");
    }
    
    /**
     * @notice Tests the node ID update functionality
     * @dev Verifies that scribes can update node IDs for existing token assignments
     */
    function test_UpdateNodeId() public {
        // First create a payment record and add token assignment
        vm.startPrank(user1);
        usdc.approve(address(nodeAsAService), type(uint256).max);
        nodeAsAService.payForNodeServices(1, 30 days, bytes32("test-subnet"));
        vm.stopPrank();
        
        uint256 tokenId = nodeLicense.mint(user1);
        
        uint256[] memory tokenIds = new uint256[](1);
        bytes[] memory nodeIds = new bytes[](1);
        tokenIds[0] = tokenId;
        nodeIds[0] = "node1";
        
        vm.prank(scribe);
        nodeAsAService.addTokenAssignments(user1, 0, tokenIds, nodeIds);
        
        // Update nodeId
        vm.prank(scribe);
        nodeAsAService.updateNodeId(user1, 0, tokenId, "node1-updated");
        
        // Verify update
        bytes memory nodeId = nodeAsAService.getNodeIdForToken(user1, 0, tokenId);
        assertEq(string(nodeId), "node1-updated");
    }
    
    /**
     * @notice Tests the fund withdrawal functionality
     * @dev Verifies that protocol managers can withdraw funds from the contract
     */
    function test_WithdrawFunds() public {
        // First create a payment to add funds to the contract
        vm.startPrank(user1);
        usdc.approve(address(nodeAsAService), type(uint256).max);
        nodeAsAService.payForNodeServices(1, 30 days, bytes32("test-subnet"));
        vm.stopPrank();
        
        uint256 contractBalance = usdc.balanceOf(address(nodeAsAService));
        uint256 managerBalance = usdc.balanceOf(protocolManager);
        
        // Withdraw funds
        vm.prank(protocolManager);
        nodeAsAService.withdrawFunds(contractBalance);
        
        // Verify withdrawal
        assertEq(usdc.balanceOf(address(nodeAsAService)), 0);
        assertEq(usdc.balanceOf(protocolManager), managerBalance + contractBalance);
    }
    
    /**
     * @notice Tests the license price update functionality
     * @dev Verifies that admins can update the license price per month
     */
    function test_UpdateLicensePrice() public {
        uint256 newPrice = 200 * 1e6; // 200 USDC
        
        vm.prank(admin);
        nodeAsAService.setLicensePricePerMonth(newPrice);
        
        assertEq(nodeAsAService.licensePricePerMonth(), newPrice);
    }
    
    /**
     * @notice Tests that payment for node services reverts with zero license count
     * @dev Verifies the MustPayForAtLeastOneLicense error is thrown
     */
    function test_RevertWhen_PayForNodeServices_ZeroLicenseCount() public {
        vm.prank(user1);
        vm.expectRevert(NodeAsAService.MustPayForAtLeastOneLicense.selector);
        nodeAsAService.payForNodeServices(0, 30 days, bytes32("test-subnet"));
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
     * @notice Tests that non-scribes cannot add token assignments
     * @dev Verifies the AccessControlUnauthorizedAccount error is thrown
     */
    function test_RevertWhen_AddTokenAssignments_NotScribe() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user1, SCRIBE_ROLE));
        nodeAsAService.addTokenAssignments(user1, 0, new uint256[](1), new bytes[](1));
    }
    
    /**
     * @notice Tests that non-scribes cannot update node IDs
     * @dev Verifies the AccessControlUnauthorizedAccount error is thrown
     */
    function test_RevertWhen_UpdateNodeId_NotScribe() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user1, SCRIBE_ROLE));
        nodeAsAService.updateNodeId(user1, 0, 1, bytes("node1"));
    }
    
    /**
     * @notice Tests that non-protocol managers cannot withdraw funds
     * @dev Verifies the AccessControlUnauthorizedAccount error is thrown
     */
    function test_RevertWhen_WithdrawFunds_NotProtocolManager() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user1, PROTOCOL_MANAGER_ROLE));
        nodeAsAService.withdrawFunds(100);
    }

    /**
     * @notice Tests that payment for node services reverts with too many licenses
     * @dev Verifies the TooManyLicenses error is thrown when license count exceeds 100
     */
    function test_RevertWhen_PayForNodeServices_TooManyLicenses() public {
        vm.prank(user1);
        vm.expectRevert(NodeAsAService.TooManyLicenses.selector);
        nodeAsAService.payForNodeServices(101, 30 days, bytes32("test-subnet"));
    }

    /**
     * @notice Tests that payment for node services reverts with insufficient balance
     * @dev Verifies the InsufficientBalance error is thrown when user has insufficient USDC
     */
    function test_RevertWhen_PayForNodeServices_InsufficientBalance() public {
        vm.prank(user2);
        // Try to pay for a large number of licenses to exceed balance
        vm.expectRevert(NodeAsAService.InsufficientBalance.selector);
        nodeAsAService.payForNodeServices(100, 30 days, bytes32("test-subnet"));
    }

    /**
     * @notice Tests that payment for node services reverts with transfer failure
     * @dev Verifies the TransferFailed error is thrown when USDC transfer fails
     */
    function test_RevertWhen_PayForNodeServices_TransferFailed() public {
        // First approve spending
        vm.startPrank(user1);
        usdc.approve(address(nodeAsAService), type(uint256).max);
        vm.stopPrank();

        // Set transfer to fail
        usdc.setTransferShouldFail(true);

        vm.prank(user1);
        vm.expectRevert(NodeAsAService.TransferFailed.selector);
        nodeAsAService.payForNodeServices(1, 30 days, bytes32("test-subnet"));
    }

    /**
     * @notice Tests that token assignment reverts with empty token IDs array
     * @dev Verifies the EmptyTokenIds error is thrown
     */
    function test_RevertWhen_AddTokenAssignments_EmptyTokenIds() public {
        vm.prank(scribe);
        vm.expectRevert(NodeAsAService.EmptyTokenIds.selector);
        nodeAsAService.addTokenAssignments(user1, 0, new uint256[](0), new bytes[](0));
    }

    /**
     * @notice Tests that token assignment reverts with token ID not found
     * @dev Verifies the TokenIdNotFound error is thrown
     */
    function test_RevertWhen_UpdateNodeId_TokenIdNotFound() public {
        // First create a payment record
        vm.startPrank(user1);
        usdc.approve(address(nodeAsAService), type(uint256).max);
        nodeAsAService.payForNodeServices(1, 30 days, bytes32("test-subnet"));
        vm.stopPrank();

        // Try to update a non-existent token ID
        vm.prank(scribe);
        vm.expectRevert(NodeAsAService.TokenIdNotFound.selector);
        nodeAsAService.updateNodeId(user1, 0, 999, bytes("node1")); // Non-existent token ID
    }

    /**
     * @notice Tests that token assignment reverts with token ID/node ID mismatch
     * @dev Verifies the TokenIdNodeIdMismatch error is thrown
     */
    function test_RevertWhen_AddTokenAssignments_TokenIdNodeIdMismatch() public {
        uint256[] memory tokenIds = new uint256[](1);
        bytes[] memory nodeIds = new bytes[](2); // Different length
        vm.prank(scribe);
        vm.expectRevert(NodeAsAService.TokenIdNodeIdMismatch.selector);
        nodeAsAService.addTokenAssignments(user1, 0, tokenIds, nodeIds);
    }

    /**
     * @notice Tests that token assignment reverts with invalid payment record index
     * @dev Verifies the InvalidPaymentRecordIndex error is thrown
     */
    function test_RevertWhen_AddTokenAssignments_InvalidPaymentRecordIndex() public {
        vm.prank(scribe);
        vm.expectRevert(NodeAsAService.InvalidPaymentRecordIndex.selector);
        nodeAsAService.addTokenAssignments(user1, 1, new uint256[](1), new bytes[](1)); // Non-existent index
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
     * @notice Tests that license price update reverts with zero price
     * @dev Verifies the InvalidPrice error is thrown
     */
    function test_RevertWhen_UpdateLicensePrice_ZeroPrice() public {
        vm.prank(admin);
        vm.expectRevert(NodeAsAService.InvalidPrice.selector);
        nodeAsAService.setLicensePricePerMonth(0);
    }

    /**
     * @notice Tests setting a new scribe
     * @dev Verifies that admin can set a new scribe and the role is granted correctly
     */
    function test_SetNewScribe() public {
        address newScribe = makeAddr("newScribe");
        vm.prank(admin);
        nodeAsAService.setContractScribe(newScribe);
        assertTrue(nodeAsAService.hasRole(nodeAsAService.SCRIBE_ROLE(), newScribe));
    }

    /**
     * @notice Tests setting a new protocol manager
     * @dev Verifies that admin can set a new protocol manager and the role is granted correctly
     */
    function test_SetNewProtocolManager() public {
        address newManager = makeAddr("newManager");
        vm.prank(admin);
        nodeAsAService.setProtocolManager(newManager);
        assertTrue(nodeAsAService.hasRole(nodeAsAService.PROTOCOL_MANAGER_ROLE(), newManager));
    }

    /**
     * @notice Tests that setting scribe reverts with zero address
     * @dev Verifies the ZeroAddress error is thrown
     */
    function test_RevertWhen_SetScribe_ZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(NodeAsAService.ZeroAddress.selector);
        nodeAsAService.setContractScribe(address(0));
    }

    /**
     * @notice Tests that setting protocol manager reverts with zero address
     * @dev Verifies the ZeroAddress error is thrown
     */
    function test_RevertWhen_SetProtocolManager_ZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(NodeAsAService.ZeroAddress.selector);
        nodeAsAService.setProtocolManager(address(0));
    }

    /**
     * @notice Tests that multiple tokens can be assigned to the same node ID
     * @dev Verifies that the same node ID can be used for different token IDs
     */
    function test_MultipleTokensPerNodeId() public {
        // First create a payment record
        vm.startPrank(user1);
        usdc.approve(address(nodeAsAService), type(uint256).max);
        nodeAsAService.payForNodeServices(2, 30 days, bytes32("test-subnet"));
        vm.stopPrank();
        
        // Mint two tokens
        uint256 tokenId1 = nodeLicense.mint(user1);
        uint256 tokenId2 = nodeLicense.mint(user1);
        
        // Assign both tokens to the same node ID
        uint256[] memory tokenIds = new uint256[](2);
        bytes[] memory nodeIds = new bytes[](2);
        tokenIds[0] = tokenId1;
        tokenIds[1] = tokenId2;
        nodeIds[0] = "same-node";
        nodeIds[1] = "same-node";
        
        vm.prank(scribe);
        nodeAsAService.addTokenAssignments(user1, 0, tokenIds, nodeIds);
        
        // Verify both tokens have the same node ID
        bytes memory nodeId1 = nodeAsAService.getNodeIdForToken(user1, 0, tokenId1);
        bytes memory nodeId2 = nodeAsAService.getNodeIdForToken(user1, 0, tokenId2);
        assertEq(string(nodeId1), "same-node");
        assertEq(string(nodeId2), "same-node");
    }
} 