// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Certificates} from "../contracts/tokens/Certificates.sol";
import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts@5.0.2/proxy/ERC1967/ERC1967Proxy.sol";

contract CertificateMultiMintTest is Test {
    Certificates public certificates;
    address public admin;

    function setUp() public {
        admin = makeAddr("admin");
        certificates = new Certificates();

        bytes memory initData = abi.encodeWithSelector(
            Certificates.initialize.selector,
            admin,
            admin,
            admin,
            "https://certs.com"
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(certificates), initData);

        // Get the proxy address as our main contract instance
        certificates = Certificates(address(proxy));
    }

    function test_mintMultipleCollections() public {
        // Create test addresses
        address alice = makeAddr("Alice");
        address bob = makeAddr("Bob");

        // Test minting to multiple collections for Alice
        vm.startPrank(admin);
        certificates.safeMint(alice, "collection_1");
        certificates.safeMint(alice, "collection_2");
        certificates.safeMint(alice, "collection_3");
        vm.stopPrank();

        // Verify Alice's mints
        assertEq(certificates.tokenByCollection(alice, "collection_1"), 1);
        assertEq(certificates.tokenByCollection(alice, "collection_2"), 2);
        assertEq(certificates.tokenByCollection(alice, "collection_3"), 3);
        assertEq(certificates.ownerOf(1), alice);
        assertEq(certificates.ownerOf(2), alice);
        assertEq(certificates.ownerOf(3), alice);
        assertEq(certificates.balanceOf(alice), 3);

        // Test minting to multiple collections for Bob
        vm.startPrank(admin);
        certificates.safeMint(bob, "collection_1");
        certificates.safeMint(bob, "collection_4");
        vm.stopPrank();

        // Verify Bob's mints
        assertEq(certificates.tokenByCollection(bob, "collection_1"), 4);
        assertEq(certificates.tokenByCollection(bob, "collection_4"), 5);
        assertEq(certificates.ownerOf(4), bob);
        assertEq(certificates.ownerOf(5), bob);
        assertEq(certificates.balanceOf(bob), 2);

        // Test burning one of Alice's collections
        vm.prank(admin);
        certificates.burnForUser(alice, "collection_2");

        // Verify state after burn
        assertEq(certificates.tokenByCollection(alice, "collection_1"), 1);
        assertEq(certificates.tokenByCollection(alice, "collection_2"), 0);
        assertEq(certificates.tokenByCollection(alice, "collection_3"), 3);
        assertEq(certificates.balanceOf(alice), 2);

        // Verify Bob's tokens remain unchanged
        assertEq(certificates.tokenByCollection(bob, "collection_1"), 4);
        assertEq(certificates.tokenByCollection(bob, "collection_4"), 5);
        assertEq(certificates.balanceOf(bob), 2);
    }
    // Is there ever a case in which one address would require multiple of the same NFTs
    function test_mintMultipleCollections_revert() public {
        address alice = makeAddr("Alice");

        // Mint first collection
        vm.prank(admin);
        certificates.safeMint(alice, "collection_1");

        // Try to mint same collection again - should revert
        vm.prank(admin);
        vm.expectRevert(
            "This collection already has a token for this address."
        );
        certificates.safeMint(alice, "collection_1");

        // Verify original mint still exists
        assertEq(certificates.tokenByCollection(alice, "collection_1"), 1);
        assertEq(certificates.balanceOf(alice), 1);
    }
}
