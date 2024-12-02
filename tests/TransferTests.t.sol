// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Certificates} from "../contracts/tokens/Certificates.sol";
import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts@5.0.2/proxy/ERC1967/ERC1967Proxy.sol";

contract CertificateTransferTest is Test {
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
        certificates = Certificates(address(proxy));
    }

    function test_transfer_reverts_soulbound() public {
        // Create test addresses
        address alice = makeAddr("Alice");
        address bob = makeAddr("Bob");

        // Mint a token to Alice
        vm.prank(admin);
        certificates.safeMint(alice, "collection_1");

        // Verify initial ownership
        assertEq(certificates.tokenByCollection(alice, "collection_1"), 1);
        assertEq(certificates.ownerOf(1), alice);
        assertEq(certificates.balanceOf(alice), 1);

        // Attempt to transfer - should revert due to soulbound nature
        vm.prank(alice);
        vm.expectRevert("This a Soulbound token. It cannot be transferred.");
        certificates.transferFrom(alice, bob, 1);

        // Verify ownership remains unchanged
        assertEq(certificates.tokenByCollection(alice, "collection_1"), 1);
        assertEq(certificates.ownerOf(1), alice);
        assertEq(certificates.balanceOf(alice), 1);
        assertEq(certificates.balanceOf(bob), 0);
    }

    function test_transfer_reverts_even_with_approval() public {
        address alice = makeAddr("Alice");
        address bob = makeAddr("Bob");

        // Mint a token to Alice
        vm.prank(admin);
        certificates.safeMint(alice, "collection_1");

        // Alice approves Bob
        vm.prank(alice);
        certificates.approve(bob, 1);

        // Attempt transfer with approval - should still revert
        vm.prank(bob);
        vm.expectRevert("This a Soulbound token. It cannot be transferred.");
        certificates.transferFrom(alice, bob, 1);

        // Verify ownership remains unchanged
        assertEq(certificates.tokenByCollection(alice, "collection_1"), 1);
        assertEq(certificates.ownerOf(1), alice);
        assertEq(certificates.balanceOf(alice), 1);
        assertEq(certificates.balanceOf(bob), 0);
    }
}
