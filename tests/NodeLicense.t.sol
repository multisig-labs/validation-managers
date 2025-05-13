// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

import { NodeLicense, NodeLicenseSettings } from "../contracts/tokens/NodeLicense.sol";
import { MockStakingManager } from "./mocks/MockStakingManager.sol";
import { IAccessControl } from "@openzeppelin-contracts-5.3.0/access/IAccessControl.sol";
import { IERC721Errors } from "@openzeppelin-contracts-5.3.0/interfaces/draft-IERC6093.sol";

import { ERC1967Proxy } from
  "../dependencies/@openzeppelin-contracts-5.3.0/proxy/ERC1967/ERC1967Proxy.sol";
import { Base } from "./utils/Base.sol";

contract NodeLicenseTest is Base {
  NodeLicense public nodeLicense;
  MockStakingManager public mockStakingManager;
  address public minter;
  address public admin;
  address public user1;
  address public user2;

  function setUp() public override {
    super.setUp();

    minter = makeAddr("minter");
    admin = makeAddr("admin");
    user1 = makeAddr("user1");
    user2 = makeAddr("user2");

    mockStakingManager = new MockStakingManager();

    NodeLicenseSettings memory settings = NodeLicenseSettings({
      admin: admin,
      minter: minter,
      nftStakingManager: address(mockStakingManager),
      name: "Node License",
      symbol: "NODE",
      baseTokenURI: "https://example.com/token/",
      unlockTime: 0,
      defaultAdminDelay: 0
    });

    // Deploy the implementation contract
    NodeLicense implementation = new NodeLicense();

    // Deploy the proxy contract
    bytes memory data = abi.encodeWithSelector(NodeLicense.initialize.selector, settings);

    // Deploy the proxy and initialize it
    nodeLicense = NodeLicense(address(new ERC1967Proxy(address(implementation), data)));
  }

  function test_Initialization() public view {
    assertEq(nodeLicense.name(), "Node License");
    assertEq(nodeLicense.symbol(), "NODE");
    assertEq(nodeLicense.hasRole(nodeLicense.DEFAULT_ADMIN_ROLE(), admin), true);
    assertEq(nodeLicense.hasRole(nodeLicense.MINTER_ROLE(), minter), true);
  }

  function test_Mint() public {
    vm.prank(minter);
    uint256 tokenId = nodeLicense.mint(user1);

    assertEq(tokenId, 1);
    assertEq(nodeLicense.ownerOf(tokenId), user1);
    assertEq(nodeLicense.balanceOf(user1), 1);
  }

  function test_Mint_NotMinter() public {
    vm.expectRevert();
    nodeLicense.mint(user1);
  }

  function test_BatchMint() public {
    address[] memory recipients = new address[](2);
    uint256[] memory amounts = new uint256[](2);

    recipients[0] = user1;
    recipients[1] = user2;
    amounts[0] = 2;
    amounts[1] = 3;

    vm.prank(minter);
    nodeLicense.batchMint(recipients, amounts);

    // Verify all tokens were minted correctly
    assertEq(nodeLicense.balanceOf(user1), 2);
    assertEq(nodeLicense.balanceOf(user2), 3);

    // Verify token ownership
    assertEq(nodeLicense.ownerOf(1), user1);
    assertEq(nodeLicense.ownerOf(2), user1);
    assertEq(nodeLicense.ownerOf(3), user2);
    assertEq(nodeLicense.ownerOf(4), user2);
    assertEq(nodeLicense.ownerOf(5), user2);
  }

  function test_BatchMint_InvalidInputs() public {
    // Test empty arrays
    address[] memory recipients = new address[](0);
    uint256[] memory amounts = new uint256[](0);

    vm.prank(minter);
    vm.expectRevert();
    nodeLicense.batchMint(recipients, amounts);

    // Test mismatched array lengths
    recipients = new address[](2);
    amounts = new uint256[](1);
    vm.prank(minter);
    vm.expectRevert();
    nodeLicense.batchMint(recipients, amounts);
  }

  function test_BatchTransfer() public {
    vm.prank(minter);
    nodeLicense.mint(user1);
    vm.prank(minter);
    nodeLicense.mint(user1);

    uint256[] memory tokenIds = new uint256[](2);
    tokenIds[0] = 1;
    tokenIds[1] = 2;

    vm.prank(user1);
    nodeLicense.batchTransferFrom(user1, user2, tokenIds);

    assertEq(nodeLicense.ownerOf(1), user2);
    assertEq(nodeLicense.ownerOf(2), user2);
    assertEq(nodeLicense.balanceOf(user1), 0);
    assertEq(nodeLicense.balanceOf(user2), 2);
  }

  function test_Transfer_StakedToken() public {
    vm.prank(minter);
    uint256 tokenId = nodeLicense.mint(user1);

    bytes32 lockId = keccak256("test-lock");
    vm.prank(address(mockStakingManager));
    mockStakingManager.setTokenLocked(tokenId, lockId);

    vm.prank(user1);
    vm.expectRevert();
    nodeLicense.transferFrom(user1, user2, tokenId);
  }

  function test_Transfer_LockedToken() public {
    NodeLicenseSettings memory settings = NodeLicenseSettings({
      admin: admin,
      minter: minter,
      nftStakingManager: address(mockStakingManager),
      name: "Node License",
      symbol: "NODE",
      baseTokenURI: "https://example.com/token/",
      unlockTime: uint32(block.timestamp + 1 days),
      defaultAdminDelay: 0
    });

    // Deploy the implementation contract
    NodeLicense implementation = new NodeLicense();

    // Deploy the proxy contract
    bytes memory data = abi.encodeWithSelector(NodeLicense.initialize.selector, settings);

    // Deploy the proxy and initialize it
    NodeLicense lockedLicense =
      NodeLicense(address(new ERC1967Proxy(address(implementation), data)));

    vm.prank(minter);
    uint256 tokenId = lockedLicense.mint(user1);

    vm.prank(user1);
    vm.expectRevert();
    lockedLicense.transferFrom(user1, user2, tokenId);
  }

  function test_Approve() public {
    vm.prank(minter);
    uint256 tokenId = nodeLicense.mint(user1);

    vm.prank(user1);
    nodeLicense.approve(user2, tokenId);

    assertEq(nodeLicense.getApproved(tokenId), user2);
  }

  function test_SetApprovalForAll() public {
    vm.prank(minter);
    nodeLicense.mint(user1);

    vm.prank(user1);
    nodeLicense.setApprovalForAll(user2, true);

    assertEq(nodeLicense.isApprovedForAll(user1, user2), true);
  }

  function test_Burn() public {
    vm.prank(minter);
    uint256 tokenId = nodeLicense.mint(user1);

    vm.prank(minter);
    nodeLicense.burn(tokenId);

    vm.expectRevert();
    nodeLicense.ownerOf(tokenId);
  }

  function test_SetBaseURI() public {
    vm.prank(admin);
    nodeLicense.setBaseURI("https://new-uri.com/");

    vm.prank(minter);
    uint256 tokenId = nodeLicense.mint(user1);

    assertEq(nodeLicense.tokenURI(tokenId), "https://new-uri.com/1");
  }

  function test_SetNFTStakingManager() public {
    // Mint a token to user1
    vm.prank(minter);
    uint256 tokenId = nodeLicense.mint(user1);

    // Lock the token in the original staking manager
    bytes32 lockId = keccak256("test-lock");
    vm.prank(address(mockStakingManager));
    mockStakingManager.setTokenLocked(tokenId, lockId);

    // Try to transfer - should fail because token is locked
    vm.prank(user1);
    vm.expectRevert();
    nodeLicense.transferFrom(user1, user2, tokenId);

    // Deploy a new staking manager
    MockStakingManager newStakingManager = new MockStakingManager();

    // Update the staking manager in NodeLicense
    vm.prank(admin);
    nodeLicense.setNFTStakingManager(address(newStakingManager));

    // Try to transfer - should succeed because token is not locked in the new staking manager
    vm.prank(user1);
    nodeLicense.transferFrom(user1, user2, tokenId);

    // Verify the transfer was successful
    assertEq(nodeLicense.ownerOf(tokenId), user2);
  }

  function test_SetUnlockTime() public {
    // Get current unlock time (should be 0 from setup)
    assertEq(nodeLicense.getUnlockTime(), 0);

    // Set new unlock time
    uint32 newUnlockTime = uint32(block.timestamp + 1 days);
    vm.prank(admin);
    nodeLicense.setUnlockTime(newUnlockTime);

    // Verify unlock time was updated
    assertEq(nodeLicense.getUnlockTime(), newUnlockTime);

    // Mint a token
    vm.prank(minter);
    uint256 tokenId = nodeLicense.mint(user1);

    // Try to transfer - should fail because token is locked
    vm.prank(user1);
    vm.expectRevert();
    nodeLicense.transferFrom(user1, user2, tokenId);

    // Warp time forward past unlock time
    vm.warp(block.timestamp + 2 days);

    // Try to transfer again - should succeed
    vm.prank(user1);
    nodeLicense.transferFrom(user1, user2, tokenId);

    // Verify transfer was successful
    assertEq(nodeLicense.ownerOf(tokenId), user2);
  }

  function test_SetUnlockTime_NotAdmin() public {
    uint32 newUnlockTime = uint32(block.timestamp + 1 days);

    // Try to set unlock time as non-admin
    vm.startPrank(user1);
    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector, user1, nodeLicense.DEFAULT_ADMIN_ROLE()
      )
    );
    nodeLicense.setUnlockTime(newUnlockTime);
    vm.stopPrank();


    // Verify unlock time was not changed
    assertEq(nodeLicense.getUnlockTime(), 0);
  }

  function test_TransferClearsApprovals() public {
    vm.prank(minter);
    uint256 tokenId = nodeLicense.mint(user1);

    // User1 approves user2 for the token
    vm.prank(user1);
    nodeLicense.approve(user2, tokenId);
    assertEq(nodeLicense.getApproved(tokenId), user2, "User2 should be approved before transfer");

    // User1 approves user2 for delegation
    vm.prank(user1);
    nodeLicense.approveDelegation(user2, tokenId);
    assertEq(nodeLicense.getDelegationApproval(tokenId), user2, "User2 should be delegation approved before transfer");

    // User1 transfers the token to user2
    vm.prank(user1);
    nodeLicense.transferFrom(user1, user2, tokenId);

    // Verify approvals are cleared
    assertEq(nodeLicense.getApproved(tokenId), address(0), "Standard approval should be cleared after transfer");
    // Delegation approval is cleared by _update calling _approveDelegation(address(0), tokenId, address(0))
    // but getDelegationApproval requires the caller to be the owner, which is now user2.
    // So we check it as user2.
    vm.prank(user2);
    assertEq(nodeLicense.getDelegationApproval(tokenId), address(0), "Delegation approval should be cleared after transfer");
  }
  // --- Tests for Delegation Approval ---

  function test_ApproveDelegation_And_GetDelegationApproval() public {
    // Mint a token to user1
    vm.prank(minter);
    uint256 tokenId = nodeLicense.mint(user1);

    // user1 approves user2 for this specific token
    vm.prank(user1);
    vm.expectEmit(true, true, true, true);
    emit NodeLicense.DelegateApproval(user1, user2, tokenId);
    nodeLicense.approveDelegation(user2, tokenId);

    // Verify user2 is the approved delegate for the token
    assertEq(nodeLicense.getDelegationApproval(tokenId), user2, "User2 should be approved delegate");

    // user1 changes approval to address(0) (clearing it)
    vm.prank(user1);
    vm.expectEmit(true, true, true, true);
    emit NodeLicense.DelegateApproval(user1, address(0), tokenId);
    nodeLicense.approveDelegation(address(0), tokenId);
    assertEq(
      nodeLicense.getDelegationApproval(tokenId),
      address(0),
      "Delegation approval should be cleared"
    );
  }

  function test_ApproveDelegation_NotOwner_Reverts() public {
    // Mint a token to user1
    vm.prank(minter);
    uint256 tokenId = nodeLicense.mint(user1);

    // user2 (not owner) tries to approve user1 for the token
    vm.prank(user2);
    vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InvalidApprover.selector, user2));
    nodeLicense.approveDelegation(user1, tokenId);
  }

  function test_GetDelegationApproval_NonExistentToken_Reverts() public {
    // Mint token 1 to user1 so that token IDs start from 1
    vm.prank(minter);
    nodeLicense.mint(user1);

    // Try to get approval for a non-existent token (e.g., tokenId 99)
    // _requireOwned inside getDelegationApproval should revert
    uint256 nonExistentTokenId = 99;
    vm.expectRevert(
      abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, nonExistentTokenId)
    );
    nodeLicense.getDelegationApproval(nonExistentTokenId);
  }
  
  function test_RemoveDelegaation_NonExistantDelegation() public {
    address operator = makeAddr("operator");

    vm.prank(minter);
    nodeLicense.mint(user1);
    
    vm.prank(user1);
    nodeLicense.setDelegationApprovalForAll(operator, false);
    
    assertFalse(nodeLicense.isDelegationApprovedForAll(user1, operator), "operator is not approved for user1");
  }

  function test_SetDelegationApprovalForAll_And_IsDelegationApprovedForAll() public {
    address operator1 = user2; // Using user2 as operator1 for clarity
    address operator2 = makeAddr("operator2");
    address operator3 = makeAddr("operator3");

    // Initially, no operators are approved for user1
    assertFalse(nodeLicense.isDelegationApprovedForAll(user1, operator1), "Initially operator1 not approved for user1");
    assertFalse(nodeLicense.isDelegationApprovedForAll(user1, operator2), "Initially operator2 not approved for user1");
    address[] memory initialOperators = nodeLicense.getDelegateOperatorsForOwner(user1);
    assertEq(initialOperators.length, 0, "Initially no operators for user1");

    // user1 approves operator1
    vm.prank(user1);
    vm.expectEmit(true, true, true, true);
    emit NodeLicense.DelegateApprovalForAll(user1, operator1, true);
    nodeLicense.setDelegationApprovalForAll(operator1, true);

    assertTrue(nodeLicense.isDelegationApprovedForAll(user1, operator1), "operator1 should be approved for user1");
    address[] memory operatorsAfterOp1 = nodeLicense.getDelegateOperatorsForOwner(user1);
    assertEq(operatorsAfterOp1.length, 1, "Should have 1 operator after approving operator1");
    assertEq(operatorsAfterOp1[0], operator1, "The operator should be operator1");

    // user1 approves operator2
    vm.prank(user1);
    vm.expectEmit(true, true, true, true);
    emit NodeLicense.DelegateApprovalForAll(user1, operator2, true);
    nodeLicense.setDelegationApprovalForAll(operator2, true);

    assertTrue(nodeLicense.isDelegationApprovedForAll(user1, operator1), "operator1 should still be approved for user1");
    assertTrue(nodeLicense.isDelegationApprovedForAll(user1, operator2), "operator2 should now be approved for user1");
    address[] memory operatorsAfterOp2 = nodeLicense.getDelegateOperatorsForOwner(user1);
    assertEq(operatorsAfterOp2.length, 2, "Should have 2 operators after approving operator2");
    // Note: EnumerableSet does not guarantee order, so we check for presence
    assertTrue(nodeLicense.isDelegationApprovedForAll(user1, operator1) && nodeLicense.isDelegationApprovedForAll(user1, operator2), "Both operators should be in the set");

    // user1 revokes operator1
    vm.prank(user1);
    vm.expectEmit(true, true, true, true);
    emit NodeLicense.DelegateApprovalForAll(user1, operator1, false);
    nodeLicense.setDelegationApprovalForAll(operator1, false);

    assertFalse(nodeLicense.isDelegationApprovedForAll(user1, operator1), "operator1 should NOT be approved after revocation");
    assertTrue(nodeLicense.isDelegationApprovedForAll(user1, operator2), "operator2 should still be approved");
    address[] memory operatorsAfterOp1Revoke = nodeLicense.getDelegateOperatorsForOwner(user1);
    assertEq(operatorsAfterOp1Revoke.length, 1, "Should have 1 operator after revoking operator1");
    assertEq(operatorsAfterOp1Revoke[0], operator2, "The remaining operator should be operator2");

    // user1 approves operator3 (to test order with operator2 still present)
    vm.prank(user1);
    nodeLicense.setDelegationApprovalForAll(operator3, true);
    assertTrue(nodeLicense.isDelegationApprovedForAll(user1, operator3), "operator3 should be approved");
    assertTrue(nodeLicense.isDelegationApprovedForAll(user1, operator2), "operator2 should still be approved");
    assertEq(nodeLicense.getDelegateOperatorsForOwner(user1).length, 2, "Should have 2 operators");

    // user1 revokes operator2
    vm.prank(user1);
    nodeLicense.setDelegationApprovalForAll(operator2, false);
    assertFalse(nodeLicense.isDelegationApprovedForAll(user1, operator2), "operator2 should be revoked");
    assertTrue(nodeLicense.isDelegationApprovedForAll(user1, operator3), "operator3 should still be approved");
    address[] memory operatorsAfterOp2Revoke = nodeLicense.getDelegateOperatorsForOwner(user1);
    assertEq(operatorsAfterOp2Revoke.length, 1, "Should have 1 operator after revoking operator2");
    assertEq(operatorsAfterOp2Revoke[0], operator3, "The remaining operator should be operator3");
    
    // Revoke last operator (operator3)
    vm.prank(user1);
    nodeLicense.setDelegationApprovalForAll(operator3, false);
    assertFalse(nodeLicense.isDelegationApprovedForAll(user1, operator3), "operator3 should be revoked");
    assertEq(nodeLicense.getDelegateOperatorsForOwner(user1).length, 0, "Should have 0 operators");

    // Check approvals for a different owner (no interference)
    assertFalse(nodeLicense.isDelegationApprovedForAll(operator1, operator2), "operator1 should not have approved operator2 for itself");
  }

  function test_SetDelegationApprovalForAll_RevertOnZeroAddressOperator() public {
    vm.prank(user1);
    vm.expectRevert(
      abi.encodeWithSelector(IERC721Errors.ERC721InvalidOperator.selector, address(0))
    );
    nodeLicense.setDelegationApprovalForAll(address(0), true);
  }
}
