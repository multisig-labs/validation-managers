// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

import { NodeLicenseGasless, NodeLicenseSettings } from "../contracts/tokens/NodeLicenseGasless.sol";
import { ERC2771ForwarderUseful } from "../contracts/utils/ERC2771ForwarderUseful.sol";
import { MockStakingManager } from "./mocks/MockStakingManager.sol";
import { Base } from "./utils/Base.sol";
import { IAccessControl } from "@openzeppelin-contracts-5.3.0/access/IAccessControl.sol";
import { IERC721Errors } from "@openzeppelin-contracts-5.3.0/interfaces/draft-IERC6093.sol";
import { ERC2771Forwarder } from "@openzeppelin-contracts-5.3.0/metatx/ERC2771Forwarder.sol";
import { ERC1967Proxy } from "@openzeppelin-contracts-5.3.0/proxy/ERC1967/ERC1967Proxy.sol";

contract NodeLicenseGaslessTest is Base {
  NodeLicenseGasless public nodeLicense;
  MockStakingManager public mockStakingManager;
  ERC2771ForwarderUseful public forwarder;
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

    forwarder = new ERC2771ForwarderUseful("forwarder");

    NodeLicenseSettings memory settings = NodeLicenseSettings({
      admin: admin,
      minter: minter,
      nftStakingManager: address(mockStakingManager),
      name: "Node License",
      symbol: "NODE",
      baseTokenURI: "https://example.com/token/",
      unlockTime: 0
    });

    // Deploy the implementation contract
    NodeLicenseGasless implementation = new NodeLicenseGasless();

    // Deploy the proxy contract
    bytes memory data =
      abi.encodeWithSelector(NodeLicenseGasless.initialize.selector, settings, address(forwarder));

    // Deploy the proxy and initialize it
    nodeLicense = NodeLicenseGasless(address(new ERC1967Proxy(address(implementation), data)));
  }

  function test_Initialization() public view {
    assertEq(nodeLicense.name(), "Node License");
    assertEq(nodeLicense.symbol(), "NODE");
    assertEq(nodeLicense.hasRole(nodeLicense.DEFAULT_ADMIN_ROLE(), admin), true);
    assertEq(nodeLicense.hasRole(nodeLicense.MINTER_ROLE(), minter), true);
  }

  function test_TrustedForwarder() public {
    assertEq(nodeLicense.trustedForwarder(), address(forwarder));

    vm.expectRevert();
    nodeLicense.setTrustedForwarder(address(0));

    vm.prank(admin);
    nodeLicense.setTrustedForwarder(address(0));
    assertEq(nodeLicense.trustedForwarder(), address(0));
  }

  function test_Gasless() public {
    uint256 alicePK = 0xa11ce;
    address alice = vm.addr(alicePK);
    vm.deal(alice, 1 ether);
    vm.prank(minter);
    nodeLicense.mint(alice);
    assertEq(nodeLicense.balanceOf(alice), 1);

    // Create the data for transferFrom
    bytes memory transferData =
      abi.encodeWithSelector(nodeLicense.transferFrom.selector, alice, user2, 1);

    // Create and sign the forward request
    ERC2771Forwarder.ForwardRequestData memory requestData = ERC2771Forwarder.ForwardRequestData({
      from: alice,
      to: address(nodeLicense),
      value: 0,
      gas: 100000,
      deadline: uint48(block.timestamp + 1 days),
      data: transferData,
      signature: bytes("")
    });

    bytes32 digest = forwarder.structHash(requestData);
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePK, digest);
    requestData.signature = abi.encodePacked(r, s, v);

    // Execute the forward request
    forwarder.execute(requestData);

    // Verify the transfer happened
    assertEq(nodeLicense.balanceOf(alice), 0);
    assertEq(nodeLicense.balanceOf(user2), 1);
    assertEq(nodeLicense.ownerOf(1), user2);
  }
}
