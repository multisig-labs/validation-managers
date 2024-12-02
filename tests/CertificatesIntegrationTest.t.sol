// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts@5.0.2/proxy/ERC1967/ERC1967Proxy.sol";
import {Certificates} from "../contracts/tokens/Certificates.sol";

contract CertificatesIntegrationTest is Test {
    Certificates public certificates;
    address public admin;

    function setUp() public {
        admin = makeAddr("admin");
        Certificates certificatesImplementation = new Certificates();

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

        certificates = Certificates(address(proxy));
    }

    // Test to check initial state with no collections
    function test_initial_no_collections() public {
        bytes32 collection = "collection_1";
        uint256 tokenId = 1;

        // Verify that no collection metadata exists initially
        assertEq(certificates.getCollectionMetadata(collection), "");

        // Verify that no token metadata exists initially
        assertEq(certificates.getTokenMetadata(tokenId), "");

        // Verify that no tokens exist initially
        address alice = makeAddr("Alice");
        assertEq(certificates.balanceOf(alice), 0);
    }

    // Test to verify single collection functionality
    function test_single_collection() public {
        address alice = makeAddr("Alice");
        bytes32 collection = "collection_1";
        string memory collectionMetadata = '{"name": "First Collection"}';
        string memory tokenMetadata = '{"name": "First Token"}';

        // Setup collection metadata
        vm.startPrank(admin);
        certificates.setCollectionMetadata(collection, collectionMetadata);

        // Mint single token
        certificates.safeMint(alice, collection);
        certificates.setTokenMetadata(1, tokenMetadata);
        vm.stopPrank();

        // Verify collection state
        assertEq(certificates.balanceOf(alice), 1);
        assertEq(certificates.tokenByCollection(alice, collection), 1);
        assertEq(certificates.ownerOf(1), alice);
        assertEq(
            certificates.getCollectionMetadata(collection),
            collectionMetadata
        );
        assertEq(certificates.getTokenMetadata(1), tokenMetadata);

        // Test burning
        vm.prank(alice);
        certificates.burnForCollection(collection);

        // Verify final state
        assertEq(certificates.balanceOf(alice), 0);
        assertEq(certificates.tokenByCollection(alice, collection), 0);
    }

    // Integration test combining multiple collections and metadata
    function test_collections_and_metadata() public {
        address alice = makeAddr("Alice");
        address bob = makeAddr("Bob");
        string memory newBaseURI = "https://new-certs.com/";
        string memory collectionMetadata = '{"name": "Test Collection"}';
        string memory tokenMetadata = '{"name": "Test Token"}';

        // Setup metadata and mint tokens
        vm.startPrank(admin);
        certificates.setBaseURI(newBaseURI);
        certificates.setCollectionMetadata("collection_1", collectionMetadata);

        certificates.safeMint(alice, "collection_1");
        certificates.safeMint(alice, "collection_2");
        certificates.safeMint(bob, "collection_1");

        certificates.setTokenMetadata(1, tokenMetadata);
        vm.stopPrank();

        // Verify complete state
        assertEq(certificates.balanceOf(alice), 2);
        assertEq(certificates.balanceOf(bob), 1);
        assertEq(
            certificates.getCollectionMetadata("collection_1"),
            collectionMetadata
        );
        assertEq(certificates.getTokenMetadata(1), tokenMetadata);
        assertEq(certificates.tokenURI(1), string.concat(newBaseURI, "1"));

        // Test burning while verifying other tokens remain intact
        vm.prank(alice);
        certificates.burnForCollection("collection_2");
        assertEq(certificates.balanceOf(alice), 1);
        assertEq(certificates.balanceOf(bob), 1);
        assertEq(certificates.tokenByCollection(bob, "collection_1"), 3);
    }

    // Integration test for full certificate lifecycle
    function test_full_lifecycle() public {
        address alice = makeAddr("Alice");
        address bob = makeAddr("Bob");
        string memory newBaseURI = "https://v2.certs.com/";
        string memory collectionMetadata = '{"name": "Advanced Collection"}';

        // Phase 1: Setup and Initial Minting
        vm.startPrank(admin);
        certificates.setBaseURI(newBaseURI);
        certificates.setCollectionMetadata("collection_1", collectionMetadata);
        certificates.safeMint(alice, "collection_1");
        certificates.safeMint(alice, "collection_2");
        certificates.safeMint(bob, "collection_1");
        vm.stopPrank();

        // Phase 2: Verify Initial State
        assertEq(certificates.balanceOf(alice), 2);
        assertEq(certificates.balanceOf(bob), 1);
        assertEq(
            certificates.getCollectionMetadata("collection_1"),
            collectionMetadata
        );

        // Phase 3: Test Transfer Restrictions
        vm.startPrank(alice);
        vm.expectRevert("This a Soulbound token. It cannot be transferred.");
        certificates.transferFrom(alice, bob, 1);
        certificates.approve(bob, 1);
        vm.stopPrank();

        vm.prank(bob);
        vm.expectRevert("This a Soulbound token. It cannot be transferred.");
        certificates.transferFrom(alice, bob, 1);

        // Phase 4: Test Burning and Final State
        vm.prank(alice);
        certificates.burnForCollection("collection_2");

        assertEq(certificates.balanceOf(alice), 1);
        assertEq(certificates.tokenByCollection(alice, "collection_1"), 1);
        assertEq(certificates.tokenByCollection(alice, "collection_2"), 0);
        assertEq(certificates.tokenByCollection(bob, "collection_1"), 3);
    }
}
