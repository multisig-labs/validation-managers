// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

import { HardwareOperatorLicense } from "../contracts/tokens/HardwareOperatorLicense.sol";
import { ERC1967Proxy } from
  "../dependencies/@openzeppelin-contracts-5.2.0/proxy/ERC1967/ERC1967Proxy.sol";
import { Base } from "./utils/Base.sol";

contract HardwareOperatorLicenseTest is Base {
  HardwareOperatorLicense public hardwareLicense;
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

    // Deploy the implementation contract
    HardwareOperatorLicense implementation = new HardwareOperatorLicense();

    // Deploy the proxy contract
    bytes memory data = abi.encodeWithSelector(
      HardwareOperatorLicense.initialize.selector,
      admin,
      minter,
      "Hardware Operator License",
      "HOL",
      "https://example.com/token/"
    );

    // Deploy the proxy and initialize it
    hardwareLicense =
      HardwareOperatorLicense(address(new ERC1967Proxy(address(implementation), data)));
  }

  function test_Initialization() public view {
    assertEq(hardwareLicense.name(), "Hardware Operator License");
    assertEq(hardwareLicense.symbol(), "HOL");
    assertEq(hardwareLicense.hasRole(hardwareLicense.DEFAULT_ADMIN_ROLE(), admin), true);
    assertEq(hardwareLicense.hasRole(hardwareLicense.MINTER_ROLE(), minter), true);
  }

  function test_Mint() public {
    vm.prank(minter);
    uint256 tokenId = hardwareLicense.mint(user1);

    assertEq(tokenId, 1);
    assertEq(hardwareLicense.ownerOf(tokenId), user1);
    assertEq(hardwareLicense.balanceOf(user1), 1);
  }

  function test_Mint_NotMinter() public {
    vm.expectRevert();
    hardwareLicense.mint(user1);
  }

  function test_Mint_ZeroAddress() public {
    vm.prank(minter);
    vm.expectRevert();
    hardwareLicense.mint(address(0));
  }

  function test_Transfer_Soulbound() public {
    vm.prank(minter);
    uint256 tokenId = hardwareLicense.mint(user1);

    // Try to transfer - should fail because it's soulbound
    vm.prank(user1);
    vm.expectRevert(HardwareOperatorLicense.SoulboundToken.selector);
    hardwareLicense.transferFrom(user1, user2, tokenId);

    // Try to approve - should fail because it's soulbound
    vm.prank(user1);
    vm.expectRevert(HardwareOperatorLicense.SoulboundToken.selector);
    hardwareLicense.approve(user2, tokenId);

    // Try to set approval for all - should fail because it's soulbound
    vm.prank(user1);
    vm.expectRevert(HardwareOperatorLicense.SoulboundToken.selector);
    hardwareLicense.setApprovalForAll(user2, true);
  }

  function test_Burn() public {
    vm.prank(minter);
    uint256 tokenId = hardwareLicense.mint(user1);

    vm.prank(minter);
    hardwareLicense.burn(tokenId);

    vm.expectRevert();
    hardwareLicense.ownerOf(tokenId);
  }

  function test_Burn_NotMinter() public {
    vm.prank(minter);
    uint256 tokenId = hardwareLicense.mint(user1);

    vm.prank(user1);
    vm.expectRevert();
    hardwareLicense.burn(tokenId);
  }

  function test_SetBaseURI() public {
    vm.prank(admin);
    hardwareLicense.setBaseURI("https://new-uri.com/");

    vm.prank(minter);
    uint256 tokenId = hardwareLicense.mint(user1);

    assertEq(hardwareLicense.tokenURI(tokenId), "https://new-uri.com/1");
  }

  function test_SetBaseURI_NotAdmin() public {
    vm.prank(user1);
    vm.expectRevert();
    hardwareLicense.setBaseURI("https://new-uri.com/");
  }
}
