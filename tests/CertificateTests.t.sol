// SPDX-License-Identifier: Ecosystem

pragma solidity 0.8.25;

import {ERC1967Proxy} from "@openzeppelin/contracts@5.0.2/proxy/ERC1967/ERC1967Proxy.sol";
import {BaseTest} from "./BaseTest.sol";
import {Certificates} from "../contracts/tokens/Certificates.sol";

contract CertificateTests is BaseTest {
  Certificates public certificates;
  address admin;

  function setUp() public {
    admin = makeActor("Joe");
    Certificates certificatesImplementation = new Certificates();
    
    // Deploy proxy and initialize in one step
    bytes memory initData = abi.encodeWithSelector(
        Certificates.initialize.selector,
        admin,
        admin,
        admin,
        "https://certs.com"
    );
    
    ERC1967Proxy proxy = new ERC1967Proxy(
        address(certificatesImplementation),
        initData
    );
    
    // Get the proxy address as our main contract instance
    certificates = Certificates(address(proxy));
  }

  function test_mint() public {
    address joe = makeActor("Joe");
    vm.startPrank(admin);
    certificates.grantMinterRoleForCollection("collection_1", admin);
    certificates.mint(joe, "collection_1");
    vm.expectRevert(bytes("Caller is not a minter for this collection."));
    certificates.mint(joe, "collection_2");

    assertEq(certificates.tokenByCollection(joe, "collection_1"), 1);
    assertEq(certificates.ownerOf(1), joe);
    // Standard func that will return 1 regardless of how many collection tokens the user has
    assertEq(certificates.balanceOf(joe), 1);
    certificates.burnForUser(joe, "collection_1");
    assertEq(certificates.balanceOf(joe), 0);
    assertEq(certificates.tokenByCollection(joe, "collection_1"), 0);
  }

  function test_mint_burn() public {
    address joe = makeActor("Joe");
    vm.startPrank(admin);
    certificates.grantMinterRoleForCollection("collection_1", admin);
    certificates.mint(joe, "collection_1");
    vm.stopPrank();

    vm.prank(joe);
    certificates.burnForCollection("collection_1");
    assertEq(certificates.balanceOf(joe), 0);
    assertEq(certificates.tokenByCollection(joe, "collection_1"), 0);
  }

}
