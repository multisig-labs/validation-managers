// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts@5.0.2/proxy/ERC1967/ERC1967Proxy.sol";
import {Certificates} from "../contracts/tokens/Certificates.sol";
import {Strings} from "@openzeppelin/contracts@5.0.2/utils/Strings.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

contract CertificatesUnitTest is Test {
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

    // Test setBaseURI
    function test_setBaseURI() public {
        string memory newBaseURI = "https://new-certs.com/";
        address alice = makeAddr("alice");

        vm.startPrank(admin);
        certificates.setBaseURI(newBaseURI);
        certificates.safeMint(alice, "collection_1");
        vm.stopPrank();
        assertEq(certificates.tokenURI(1), string.concat(newBaseURI, "1"));
    }

    function test_setBaseURI_unauthorized() public {
        string memory newBaseURI = "https://new-certs.com/";
        address unauthorized = makeAddr("unauthorized");

        vm.prank(unauthorized);
        vm.expectRevert();
        certificates.setBaseURI(newBaseURI);
    }

    // Test collection metadata
    function test_setCollectionMetadata() public {
        bytes32 collection = "collection_1";
        string memory metadata = '{"name": "Test Collection"}';

        vm.prank(admin);
        certificates.setCollectionMetadata(collection, metadata);

        assertEq(certificates.getCollectionMetadata(collection), metadata);
    }

    function test_setCollectionMetadata_unauthorized() public {
        bytes32 collection = "collection_1";
        string memory metadata = '{"name": "Test Collection"}';
        address unauthorized = makeAddr("unauthorized");

        vm.prank(unauthorized);
        vm.expectRevert();
        certificates.setCollectionMetadata(collection, metadata);
    }

    // Test token metadata
    function test_setTokenMetadata() public {
        address alice = makeAddr("alice");
        string memory tokenMetadata = '{"name": "Test Token"}';

        vm.startPrank(admin);
        certificates.safeMint(alice, "collection_1");
        certificates.setTokenMetadata(1, tokenMetadata);
        vm.stopPrank();

        assertEq(certificates.getTokenMetadata(1), tokenMetadata);
    }

    function test_setTokenMetadata_unauthorized() public {
        address alice = makeAddr("alice");
        string memory tokenMetadata = '{"name": "Test Token"}';
        address unauthorized = makeAddr("unauthorized");

        vm.prank(admin);
        certificates.safeMint(alice, "collection_1");

        vm.prank(unauthorized);
        vm.expectRevert();
        certificates.setTokenMetadata(1, tokenMetadata);
    }

    // Test minting
    function test_safeMint() public {
        address alice = makeAddr("alice");
        bytes32 collection = "collection_1";

        vm.prank(admin);
        certificates.safeMint(alice, collection);

        assertEq(certificates.balanceOf(alice), 1);
        assertEq(certificates.tokenByCollection(alice, collection), 1);
        assertEq(certificates.ownerOf(1), alice);
    }

    function test_safeMint_unauthorized() public {
        address alice = makeAddr("alice");
        bytes32 collection = "collection_1";
        address unauthorized = makeAddr("unauthorized");

        vm.prank(unauthorized);
        vm.expectRevert();
        certificates.safeMint(alice, collection);
    }

    function test_safeMint_duplicateCollection() public {
        address alice = makeAddr("alice");
        bytes32 collection = "collection_1";

        // First mint should succeed
        vm.prank(admin);
        certificates.safeMint(alice, collection);

        // Second mint to same collection/address should fail
        vm.prank(admin);
        vm.expectRevert(
            "This collection already has a token for this address."
        );
        certificates.safeMint(alice, collection);

        // Verify only one token exists
        assertEq(certificates.balanceOf(alice), 1);
        assertEq(certificates.tokenByCollection(alice, collection), 1);
    }

    // Test burning
    function test_burnForCollection() public {
        address alice = makeAddr("alice");
        bytes32 collection = "collection_1";

        vm.prank(admin);
        certificates.safeMint(alice, collection);

        vm.prank(alice);
        certificates.burnForCollection(collection);

        assertEq(certificates.balanceOf(alice), 0);
        assertEq(certificates.tokenByCollection(alice, collection), 0);
    }

    function test_burnForCollection_unauthorized() public {
        address alice = makeAddr("alice");
        address bob = makeAddr("bob");
        bytes32 collection = "collection_1";

        vm.prank(admin);
        certificates.safeMint(alice, collection);

        vm.prank(bob);
        vm.expectRevert("No token for this collection for this address.");
        certificates.burnForCollection(collection);
    }

    // Test transfer restrictions
    function test_transfer_restrictions() public {
        address alice = makeAddr("alice");
        address bob = makeAddr("bob");

        vm.prank(admin);
        certificates.safeMint(alice, "collection_1");

        vm.startPrank(alice);
        vm.expectRevert("This a Soulbound token. It cannot be transferred.");
        certificates.transferFrom(alice, bob, 1);

        vm.expectRevert("This a Soulbound token. It cannot be transferred.");
        certificates.safeTransferFrom(alice, bob, 1);

        vm.expectRevert("This a Soulbound token. It cannot be transferred.");
        certificates.safeTransferFrom(alice, bob, 1, "");
        vm.stopPrank();
    }

    // Test tokenURI
    function test_tokenURI() public {
        address alice = makeAddr("alice");

        vm.prank(admin);
        certificates.safeMint(alice, "collection_1");

        assertEq(certificates.tokenURI(1), "https://certs.com1");
    }

    function test_tokenURI_nonexistent() public {
        vm.expectRevert();
        certificates.tokenURI(1);
    }

    // Test burnForUser
    function test_burnForUser() public {
        address alice = makeAddr("alice");
        bytes32 collection = "collection_1";

        // First mint a token
        vm.prank(admin);
        certificates.safeMint(alice, collection);

        // Verify initial state
        assertEq(certificates.balanceOf(alice), 1);
        assertEq(certificates.tokenByCollection(alice, collection), 1);

        // Burn token using burnForUser
        vm.prank(admin);
        certificates.burnForUser(alice, collection);

        // Verify final state
        assertEq(certificates.balanceOf(alice), 0);
        assertEq(certificates.tokenByCollection(alice, collection), 0);
    }

    function test_burnForUser_unauthorized() public {
        address alice = makeAddr("alice");
        address unauthorized = makeAddr("unauthorized");
        bytes32 collection = "collection_1";

        // First mint a token
        vm.prank(admin);
        certificates.safeMint(alice, collection);

        // Attempt to burn with unauthorized account
        vm.prank(unauthorized);
        vm.expectRevert();
        certificates.burnForUser(alice, collection);

        // Verify token still exists
        assertEq(certificates.balanceOf(alice), 1);
        assertEq(certificates.tokenByCollection(alice, collection), 1);
    }

    function test_burnForUser_nonexistent() public {
        address alice = makeAddr("alice");
        bytes32 collection = "collection_1";

        // Attempt to burn non-existent token
        vm.prank(admin);
        vm.expectRevert();
        certificates.burnForUser(alice, collection);
    }

    // Test supportsInterface
    function test_supportsInterface() public {
        // ERC721 interface ID

        bytes4 erc721InterfaceId = 0x80ac58cd;
        // IAccessControl interface ID
        bytes4 accessControlInterfaceId = 0x7965db0b;

        assertTrue(
            certificates.supportsInterface(erc721InterfaceId),
            "Should support ERC721 interface"
        );
        assertTrue(
            certificates.supportsInterface(accessControlInterfaceId),
            "Should support AccessControl interface"
        );
    }

    // Test non-supported interface
    function test_supportsInterface_unsupported() public {
        // Random interface ID
        bytes4 randomInterfaceId = 0x12345678;

        assertFalse(
            certificates.supportsInterface(randomInterfaceId),
            "Should not support random interface"
        );
    }

    // Test upgrade authorization
    function test_upgradeAuthorization() public {
        // Deploy a new implementation
        Certificates newImplementation = new Certificates();

        // Test upgrade with authorized account
        vm.prank(admin);
        certificates.upgradeToAndCall(address(newImplementation), "");
    }

    function test_upgradeAuthorization_unauthorized() public {
        // Deploy a new implementation
        Certificates newImplementation = new Certificates();
        address unauthorized = makeAddr("unauthorized");

        // Test upgrade with unauthorized account
        vm.prank(unauthorized);
        vm.expectRevert();
        certificates.upgradeToAndCall(address(newImplementation), "");
    }
}
