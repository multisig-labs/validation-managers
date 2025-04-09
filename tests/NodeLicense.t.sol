// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

import { MockStakingManager } from "../contracts/mocks/MockStakingManager.sol";
import { NodeLicense, NodeLicenseSettings } from "../contracts/tokens/NodeLicense.sol";

import { ERC1967Proxy } from
  "../dependencies/@openzeppelin-contracts-5.2.0/proxy/ERC1967/ERC1967Proxy.sol";
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
      maxBatchSize: 100
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

    // Test batch size too large
    recipients = new address[](101);
    amounts = new uint256[](101);
    for (uint256 i = 0; i < 101; i++) {
      recipients[i] = user1;
      amounts[i] = 1;
    }
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
      maxBatchSize: 100
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
    vm.prank(user1);
    vm.expectRevert();
    nodeLicense.setUnlockTime(newUnlockTime);

    // Verify unlock time was not changed
    assertEq(nodeLicense.getUnlockTime(), 0);
  }
}
