// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

/**
 * @title NodeAsAServiceUpgradeTest
 * @notice Test suite for upgrading NodeAsAService from V1 to V2
 * @dev Tests that upgrade preserves all existing data and adds new functionality
 */
import {
  NodeAsAService as NodeAsAServiceV2, PaymentRecord
} from "../../contracts/NodeAsAService.sol";
import { NodeAsAService as NodeAsAServiceV1 } from
  "../../contracts/previous-versions/NodeAsAServiceV1.sol";

import { IAccessControl } from
  "../../dependencies/@openzeppelin-contracts-5.3.0/access/IAccessControl.sol";
import { ERC1967Proxy } from
  "../../dependencies/@openzeppelin-contracts-5.3.0/proxy/ERC1967/ERC1967Proxy.sol";

import { MockChainlinkPriceFeed } from "../mocks/MockChainlinkPriceFeed.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";
import { Base } from "../utils/Base.sol";

contract NodeAsAServiceUpgradeTest is Base {
  NodeAsAServiceV2 public nodeAsAServiceV2;
  NodeAsAServiceV1 public nodeAsAServiceV1Implementation;
  NodeAsAServiceV2 public nodeAsAServiceV2Implementation;
  ERC1967Proxy public proxy;
  MockERC20 public usdc;
  MockChainlinkPriceFeed public avaxPriceFeed;

  address public admin;
  address public protocolManager;
  address public user1;
  address public user2;
  address public treasury;

  uint256 public constant INITIAL_PRICE = 100 * 1e6; // 100 USDC per month (6 decimals)
  uint256 public constant INITIAL_PAYASYOUGO_FEE = 1.33 ether; // 1.33 AVAX per month
  uint256 public constant INITIAL_BALANCE = 1000 * 1e6; // 1000 USDC

  bytes32 public constant PROTOCOL_MANAGER_ROLE = keccak256("PROTOCOL_MANAGER_ROLE");

  // Events from V2
  event PayAsYouGoFeeUpdated(uint256 oldFee, uint256 newFee);

  /**
   * @notice Sets up the test environment with V1 deployment and sample data
   */
  function setUp() public override {
    super.setUp();

    // Setup actors
    admin = makeAddr("admin");
    protocolManager = makeAddr("protocolManager");
    user1 = makeAddr("user1");
    user2 = makeAddr("user2");
    treasury = makeAddr("treasury");

    // Deploy mock USDC and price feed
    usdc = new MockERC20("USD Coin", "USDC", 6);
    avaxPriceFeed = new MockChainlinkPriceFeed(1955483503); // ~$19.55

    // Deploy V1 implementation
    nodeAsAServiceV1Implementation = new NodeAsAServiceV1();

    // Deploy proxy with V1 initialization
    bytes memory initDataV1 = abi.encodeWithSelector(
      NodeAsAServiceV1.initialize.selector, address(usdc), admin, INITIAL_PRICE, treasury
    );
    proxy = new ERC1967Proxy(address(nodeAsAServiceV1Implementation), initDataV1);

    // Setup roles in V1
    vm.prank(admin);
    NodeAsAServiceV1(address(proxy)).grantRole(PROTOCOL_MANAGER_ROLE, protocolManager);

    // Fund users with USDC
    uint256 largeBalance = 100_000 * 1e6; // 100,000 USDC
    usdc.mint(user1, largeBalance);
    usdc.mint(user2, largeBalance);

    // Create some sample data in V1 before upgrade
    _createSampleDataInV1();
  }

  /**
   * @notice Tests the upgrade process from V1 to V2
   */
  function test_UpgradeFromV1ToV2() public {
    // Capture V1 state before upgrade
    NodeAsAServiceV1 v1Contract = NodeAsAServiceV1(address(proxy));

    // Store V1 state
    uint32 v1InvoiceNumber = v1Contract.invoiceNumber();
    uint256 v1LicensePrice = v1Contract.licensePricePerMonth();
    bool v1IsPaused = v1Contract.isPaused();
    address v1Treasury = v1Contract.treasury();
    address v1Usdc = address(v1Contract.usdc());

    // Get payment records from V1 - using raw data to avoid struct conflicts
    (
      uint8 v1Record1LicenseCount,
      uint8 v1Record1Duration,
      uint256 v1Record1TotalAmount,
      uint256 v1Record1PricePerMonth,
      address v1Record1Buyer,
      bytes32 v1Record1SubnetId
    ) = _getPaymentRecordData(v1Contract, 1);

    // Get buyer invoices from V1
    uint32[] memory v1User1Invoices = v1Contract.getInvoiceNumbers(user1);
    uint32[] memory v1User2Invoices = v1Contract.getInvoiceNumbers(user2);

    // Get contract balance
    uint256 v1ContractBalance = usdc.balanceOf(address(proxy));

    // Deploy V2 implementation
    nodeAsAServiceV2Implementation = new NodeAsAServiceV2();

    // Perform upgrade
    vm.prank(admin);
    NodeAsAServiceV1(address(proxy)).upgradeToAndCall(
      address(nodeAsAServiceV2Implementation),
      abi.encodeWithSelector(
        NodeAsAServiceV2.initializeV2.selector, address(avaxPriceFeed), INITIAL_PAYASYOUGO_FEE
      )
    );

    // Cast proxy to V2 interface
    nodeAsAServiceV2 = NodeAsAServiceV2(address(proxy));

    // Verify all V1 data is preserved
    assertEq(
      nodeAsAServiceV2.invoiceNumber(), v1InvoiceNumber, "Invoice number should be preserved"
    );
    assertEq(
      nodeAsAServiceV2.licensePricePerMonth(), v1LicensePrice, "License price should be preserved"
    );
    assertEq(nodeAsAServiceV2.isPaused(), v1IsPaused, "Pause state should be preserved");
    assertEq(nodeAsAServiceV2.treasury(), v1Treasury, "Treasury should be preserved");
    assertEq(address(nodeAsAServiceV2.usdc()), v1Usdc, "USDC address should be preserved");
    assertEq(
      usdc.balanceOf(address(proxy)), v1ContractBalance, "Contract balance should be preserved"
    );

    // Verify payment records are preserved
    PaymentRecord memory v2Record1 = nodeAsAServiceV2.getPaymentRecord(1);
    assertEq(
      v2Record1.licenseCount,
      v1Record1LicenseCount,
      "Payment record 1 license count should be preserved"
    );
    assertEq(
      v2Record1.durationInMonths, v1Record1Duration, "Payment record 1 duration should be preserved"
    );
    assertEq(
      v2Record1.totalAmountPaidInUSDC,
      v1Record1TotalAmount,
      "Payment record 1 total amount should be preserved"
    );
    assertEq(
      v2Record1.pricePerMonthInUSDC,
      v1Record1PricePerMonth,
      "Payment record 1 price per month should be preserved"
    );
    assertEq(v2Record1.buyer, v1Record1Buyer, "Payment record 1 buyer should be preserved");
    assertEq(
      v2Record1.subnetId, v1Record1SubnetId, "Payment record 1 subnet ID should be preserved"
    );

    // Verify buyer invoices are preserved
    uint32[] memory v2User1Invoices = nodeAsAServiceV2.getInvoiceNumbers(user1);
    uint32[] memory v2User2Invoices = nodeAsAServiceV2.getInvoiceNumbers(user2);

    assertEq(
      v2User1Invoices.length, v1User1Invoices.length, "User1 invoice count should be preserved"
    );
    assertEq(
      v2User2Invoices.length, v1User2Invoices.length, "User2 invoice count should be preserved"
    );

    for (uint256 i = 0; i < v1User1Invoices.length; i++) {
      assertEq(v2User1Invoices[i], v1User1Invoices[i], "User1 invoice numbers should be preserved");
    }
    for (uint256 i = 0; i < v1User2Invoices.length; i++) {
      assertEq(v2User2Invoices[i], v1User2Invoices[i], "User2 invoice numbers should be preserved");
    }

    // Verify roles are preserved
    assertTrue(
      nodeAsAServiceV2.hasRole(nodeAsAServiceV2.DEFAULT_ADMIN_ROLE(), admin),
      "Admin role should be preserved"
    );
    assertTrue(
      nodeAsAServiceV2.hasRole(PROTOCOL_MANAGER_ROLE, protocolManager),
      "Protocol manager role should be preserved"
    );

    // Verify new V2 functionality is available
    assertEq(
      nodeAsAServiceV2.payAsYouGoFeePerMonth(),
      INITIAL_PAYASYOUGO_FEE,
      "PAYG fee should be initialized"
    );
    assertEq(
      nodeAsAServiceV2.avaxPriceFeed(), address(avaxPriceFeed), "AVAX price feed should be set"
    );

    // Test new V2 function works
    uint256 avaxPrice = nodeAsAServiceV2.getAvaxUsdPrice();
    assertTrue(avaxPrice > 0, "AVAX price should be available");
  }

  /**
   * @notice Tests comprehensive fund preservation during upgrade
   */
  function test_FundPreservationDuringUpgrade() public {
    NodeAsAServiceV1 v1Contract = NodeAsAServiceV1(address(proxy));

    // Record initial contract balance from setUp (created from _createSampleDataInV1)
    uint256 initialBalance = usdc.balanceOf(address(proxy));
    assertTrue(initialBalance > 0, "Should have initial balance from sample data");

    // Add more funds through additional payments
    vm.startPrank(user1);
    usdc.approve(address(proxy), type(uint256).max);
    v1Contract.payForNodeServices(10, 12, bytes32("large-payment")); // Large payment
    vm.stopPrank();

    vm.startPrank(user2);
    usdc.approve(address(proxy), type(uint256).max);
    v1Contract.payForNodeServices(7, 24, bytes32("very-large-payment")); // Very large payment
    vm.stopPrank();

    // Record balance before upgrade
    uint256 balanceBeforeUpgrade = usdc.balanceOf(address(proxy));
    assertTrue(balanceBeforeUpgrade > initialBalance, "Balance should have increased");

    // Also record individual user payments to verify accounting
    PaymentRecord memory largePayment;
    {
      // Use a block to avoid stack too deep
      (uint8 lc1, uint8 d1, uint256 ta1, uint256 pm1, address b1, bytes32 s1) =
        _getPaymentRecordData(v1Contract, 4);
      largePayment = PaymentRecord({
        licenseCount: lc1,
        durationInMonths: d1,
        totalAmountPaidInUSDC: ta1,
        pricePerMonthInUSDC: pm1,
        buyer: b1,
        subnetId: s1
      });
    }

    // Deploy V2 implementation
    nodeAsAServiceV2Implementation = new NodeAsAServiceV2();

    // Perform upgrade
    vm.prank(admin);
    v1Contract.upgradeToAndCall(
      address(nodeAsAServiceV2Implementation),
      abi.encodeWithSelector(
        NodeAsAServiceV2.initializeV2.selector, address(avaxPriceFeed), INITIAL_PAYASYOUGO_FEE
      )
    );

    // Cast to V2
    nodeAsAServiceV2 = NodeAsAServiceV2(address(proxy));

    // Verify exact balance preservation
    uint256 balanceAfterUpgrade = usdc.balanceOf(address(proxy));
    assertEq(
      balanceAfterUpgrade, balanceBeforeUpgrade, "Exact balance must be preserved during upgrade"
    );

    // Verify payment records that contributed to the balance are intact
    PaymentRecord memory preservedLargePayment = nodeAsAServiceV2.getPaymentRecord(4);

    assertEq(
      preservedLargePayment.totalAmountPaidInUSDC,
      largePayment.totalAmountPaidInUSDC,
      "Large payment amount should be preserved"
    );

    // Verify funds are still withdrawable after upgrade
    uint256 treasuryBalanceBefore = usdc.balanceOf(treasury);

    vm.prank(protocolManager);
    nodeAsAServiceV2.withdrawFunds(balanceAfterUpgrade);

    assertEq(usdc.balanceOf(address(proxy)), 0, "Contract should be empty after withdrawal");
    assertEq(
      usdc.balanceOf(treasury),
      treasuryBalanceBefore + balanceAfterUpgrade,
      "Treasury should receive all preserved funds"
    );
  }

  /**
   * @notice Tests fund preservation with zero balance edge case
   */
  function test_FundPreservationWithZeroBalance() public {
    // Deploy fresh V1 with no payments (zero balance)
    NodeAsAServiceV1 freshV1 = new NodeAsAServiceV1();
    bytes memory initData = abi.encodeWithSelector(
      NodeAsAServiceV1.initialize.selector, address(usdc), admin, INITIAL_PRICE, treasury
    );
    ERC1967Proxy freshProxy = new ERC1967Proxy(address(freshV1), initData);

    // Verify zero balance
    assertEq(usdc.balanceOf(address(freshProxy)), 0, "Fresh contract should have zero balance");

    // Deploy V2 implementation
    NodeAsAServiceV2 v2Implementation = new NodeAsAServiceV2();

    // Perform upgrade
    vm.prank(admin);
    NodeAsAServiceV1(address(freshProxy)).upgradeToAndCall(
      address(v2Implementation),
      abi.encodeWithSelector(
        NodeAsAServiceV2.initializeV2.selector, address(avaxPriceFeed), INITIAL_PAYASYOUGO_FEE
      )
    );

    // Verify zero balance is preserved
    assertEq(
      usdc.balanceOf(address(freshProxy)), 0, "Zero balance should be preserved after upgrade"
    );

    // Verify the contract still works (can receive payments)
    NodeAsAServiceV2 freshV2 = NodeAsAServiceV2(address(freshProxy));

    vm.prank(admin);
    freshV2.grantRole(PROTOCOL_MANAGER_ROLE, protocolManager);

    vm.startPrank(user1);
    usdc.approve(address(freshProxy), 1000 * 1e6);
    freshV2.payForNodeServices(1, 1, bytes32("test-payment"));
    vm.stopPrank();

    assertTrue(
      usdc.balanceOf(address(freshProxy)) > 0, "Contract should accept payments after upgrade"
    );
  }

  /**
   * @notice Tests fund preservation with maximum realistic balance
   */
  function test_FundPreservationWithLargeBalance() public {
    NodeAsAServiceV1 v1Contract = NodeAsAServiceV1(address(proxy));

    // Create a very large balance by making many payments
    uint256 largePaymentAmount = 500_000 * 1e6; // 500,000 USDC worth of payments
    usdc.mint(user1, largePaymentAmount);
    usdc.mint(user2, largePaymentAmount);

    vm.startPrank(user1);
    usdc.approve(address(proxy), largePaymentAmount);
    // Make multiple large payments to accumulate significant balance
    v1Contract.payForNodeServices(100, 12, bytes32("massive-payment-1"));
    v1Contract.payForNodeServices(200, 6, bytes32("massive-payment-2"));
    vm.stopPrank();

    vm.startPrank(user2);
    usdc.approve(address(proxy), largePaymentAmount);
    v1Contract.payForNodeServices(150, 8, bytes32("massive-payment-3"));
    vm.stopPrank();

    // Record the large balance
    uint256 largeBalanceBeforeUpgrade = usdc.balanceOf(address(proxy));

    // Deploy V2 implementation
    nodeAsAServiceV2Implementation = new NodeAsAServiceV2();

    // Perform upgrade
    vm.prank(admin);
    v1Contract.upgradeToAndCall(
      address(nodeAsAServiceV2Implementation),
      abi.encodeWithSelector(
        NodeAsAServiceV2.initializeV2.selector, address(avaxPriceFeed), INITIAL_PAYASYOUGO_FEE
      )
    );

    // Cast to V2
    nodeAsAServiceV2 = NodeAsAServiceV2(address(proxy));

    // Verify large balance is perfectly preserved
    uint256 largeBalanceAfterUpgrade = usdc.balanceOf(address(proxy));
    assertEq(
      largeBalanceAfterUpgrade, largeBalanceBeforeUpgrade, "Large balance must be exactly preserved"
    );

    // Verify we can still withdraw the large amount
    uint256 treasuryBalanceBefore = usdc.balanceOf(treasury);

    vm.prank(protocolManager);
    nodeAsAServiceV2.withdrawFunds(largeBalanceAfterUpgrade);

    assertEq(
      usdc.balanceOf(treasury),
      treasuryBalanceBefore + largeBalanceAfterUpgrade,
      "Treasury should receive full large balance"
    );
  }

  /**
   * @notice Tests that partial fund withdrawals work correctly after upgrade
   */
  function test_PartialFundWithdrawalAfterUpgrade() public {
    // First perform upgrade to get V2
    test_UpgradeFromV1ToV2();

    uint256 totalBalance = usdc.balanceOf(address(proxy));
    assertTrue(totalBalance > 0, "Should have some balance to test with");

    // Withdraw only half the funds
    uint256 partialAmount = totalBalance / 2;
    uint256 treasuryBalanceBefore = usdc.balanceOf(treasury);

    vm.prank(protocolManager);
    nodeAsAServiceV2.withdrawFunds(partialAmount);

    // Verify partial withdrawal
    assertEq(
      usdc.balanceOf(address(proxy)),
      totalBalance - partialAmount,
      "Contract should have remaining balance"
    );
    assertEq(
      usdc.balanceOf(treasury),
      treasuryBalanceBefore + partialAmount,
      "Treasury should receive partial amount"
    );

    // Verify we can still make payments with remaining balance in contract
    vm.startPrank(user1);
    nodeAsAServiceV2.payForNodeServices(1, 1, bytes32("post-partial-withdrawal"));
    vm.stopPrank();

    // Contract balance should have increased again
    assertTrue(
      usdc.balanceOf(address(proxy)) > totalBalance - partialAmount,
      "Contract balance should increase after new payment"
    );
  }

  /**
   * @notice Tests that V2 functionality works correctly after upgrade
   */
  function test_V2FunctionalityAfterUpgrade() public {
    // First perform the upgrade
    test_UpgradeFromV1ToV2();

    // Test new PAYG fee functionality
    uint256 newPayAsYouGoFee = 2.5 ether;
    vm.prank(protocolManager);
    vm.expectEmit(true, true, true, true);
    emit PayAsYouGoFeeUpdated(INITIAL_PAYASYOUGO_FEE, newPayAsYouGoFee);
    nodeAsAServiceV2.setPayAsYouGoFeePerMonth(newPayAsYouGoFee);

    assertEq(
      nodeAsAServiceV2.payAsYouGoFeePerMonth(), newPayAsYouGoFee, "PAYG fee should be updated"
    );

    // Test payment with dynamic pricing (V2 feature)
    uint8 licenseCount = 1;
    uint8 durationInMonths = 1;
    bytes32 subnetId = bytes32("test-subnet-v2");

    // Calculate expected payment with PAYG fee
    uint256 avaxPriceInUsd = nodeAsAServiceV2.getAvaxUsdPrice();
    uint256 monthlyPAYGFee = (newPayAsYouGoFee * avaxPriceInUsd) / 1e30;
    uint256 expectedPayment =
      (nodeAsAServiceV2.licensePricePerMonth() + monthlyPAYGFee) * licenseCount * durationInMonths;

    // Make payment with V2 dynamic pricing
    vm.prank(user1);
    nodeAsAServiceV2.payForNodeServices(licenseCount, durationInMonths, subnetId);

    // Verify payment record includes dynamic pricing
    PaymentRecord memory newRecord = nodeAsAServiceV2.getPaymentRecord(4); // Should be invoice #4
    assertEq(newRecord.totalAmountPaidInUSDC, expectedPayment, "Payment should include PAYG fee");
    assertEq(newRecord.buyer, user1, "Buyer should be correct");
    assertEq(newRecord.subnetId, subnetId, "Subnet ID should be correct");
  }

  /**
   * @notice Tests that old V1 functionality still works after upgrade
   */
  function test_V1FunctionalityStillWorksAfterUpgrade() public {
    // First perform the upgrade
    test_UpgradeFromV1ToV2();

    // Test that old functions still work
    uint256 newLicensePrice = 200 * 1e6;
    vm.prank(protocolManager);
    nodeAsAServiceV2.setLicensePricePerMonth(newLicensePrice);
    assertEq(
      nodeAsAServiceV2.licensePricePerMonth(), newLicensePrice, "License price update should work"
    );

    // Test pause functionality
    vm.prank(protocolManager);
    nodeAsAServiceV2.setPaused(true);
    assertTrue(nodeAsAServiceV2.isPaused(), "Contract should be paused");

    // Test that paused contract prevents payments
    vm.prank(user1);
    vm.expectRevert(NodeAsAServiceV2.ContractPaused.selector);
    nodeAsAServiceV2.payForNodeServices(1, 1, bytes32("should-fail"));

    // Unpause and test payment works
    vm.prank(protocolManager);
    nodeAsAServiceV2.setPaused(false);
    assertFalse(nodeAsAServiceV2.isPaused(), "Contract should be unpaused");

    // Test fund withdrawal still works
    uint256 contractBalance = usdc.balanceOf(address(proxy));
    uint256 treasuryBalanceBefore = usdc.balanceOf(treasury);

    vm.prank(protocolManager);
    nodeAsAServiceV2.withdrawFunds(contractBalance);

    assertEq(usdc.balanceOf(address(proxy)), 0, "Contract balance should be zero");
    assertEq(
      usdc.balanceOf(treasury),
      treasuryBalanceBefore + contractBalance,
      "Treasury should receive funds"
    );
  }

  /**
   * @notice Tests that upgrade fails with incorrect permissions
   */
  function test_RevertWhen_UpgradeWithoutPermission() public {
    nodeAsAServiceV2Implementation = new NodeAsAServiceV2();

    // Try to upgrade without admin role - use the test contract address since that's what's actually calling
    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        address(this), // The test contract is the actual caller
        NodeAsAServiceV1(address(proxy)).DEFAULT_ADMIN_ROLE()
      )
    );
    NodeAsAServiceV1(address(proxy)).upgradeToAndCall(
      address(nodeAsAServiceV2Implementation),
      abi.encodeWithSelector(
        NodeAsAServiceV2.initializeV2.selector, address(avaxPriceFeed), INITIAL_PAYASYOUGO_FEE
      )
    );
  }

  /**
   * @notice Tests that invoice numbering continues correctly after upgrade
   */
  function test_InvoiceNumberingContinuesAfterUpgrade() public {
    // Capture the next invoice number before upgrade
    uint32 nextInvoiceNumber = NodeAsAServiceV1(address(proxy)).invoiceNumber();

    // Perform upgrade
    test_UpgradeFromV1ToV2();

    // Make a new payment and verify invoice number continues
    vm.prank(user2);
    nodeAsAServiceV2.payForNodeServices(1, 1, bytes32("continuation-test"));

    PaymentRecord memory newRecord = nodeAsAServiceV2.getPaymentRecord(nextInvoiceNumber);
    assertEq(newRecord.buyer, user2, "New payment should use correct invoice number");
    assertEq(
      nodeAsAServiceV2.invoiceNumber(),
      nextInvoiceNumber + 1,
      "Invoice number should increment correctly"
    );
  }

  /**
   * @notice Creates sample payment data in V1 to test data preservation
   */
  function _createSampleDataInV1() internal {
    NodeAsAServiceV1 v1Contract = NodeAsAServiceV1(address(proxy));

    // User1 makes a payment
    vm.startPrank(user1);
    usdc.approve(address(proxy), type(uint256).max);
    v1Contract.payForNodeServices(5, 3, bytes32("subnet-1")); // 5 licenses for 3 months
    vm.stopPrank();

    // User2 makes a payment
    vm.startPrank(user2);
    usdc.approve(address(proxy), type(uint256).max);
    v1Contract.payForNodeServices(2, 6, bytes32("subnet-2")); // 2 licenses for 6 months
    vm.stopPrank();

    // Protocol manager updates price
    vm.prank(protocolManager);
    v1Contract.setLicensePricePerMonth(150 * 1e6); // Update to 150 USDC

    // User1 makes another payment with new price
    vm.prank(user1);
    v1Contract.payForNodeServices(1, 1, bytes32("subnet-3")); // 1 license for 1 month
  }

  /**
   * @notice Helper function to extract payment record data from V1 contract
   */
  function _getPaymentRecordData(NodeAsAServiceV1 v1Contract, uint32 invoiceNumber)
    internal
    view
    returns (
      uint8 licenseCount,
      uint8 durationInMonths,
      uint256 totalAmountPaidInUSDC,
      uint256 pricePerMonthInUSDC,
      address buyer,
      bytes32 subnetId
    )
  {
    // Use low-level call to get the payment record data
    bytes memory data = abi.encodeWithSignature("getPaymentRecord(uint32)", invoiceNumber);
    (bool success, bytes memory result) = address(v1Contract).staticcall(data);
    require(success, "Failed to get payment record");

    return abi.decode(result, (uint8, uint8, uint256, uint256, address, bytes32));
  }
}
