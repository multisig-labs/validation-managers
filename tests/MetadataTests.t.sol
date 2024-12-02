// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Certificates} from "../contracts/tokens/Certificates.sol";
import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts@5.0.2/proxy/ERC1967/ERC1967Proxy.sol";

contract CertificateMetadataTest is Test {
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

    function test_setBaseURI() public {
        string memory newBaseURI = "https://new-certs.com/";

        // Only admin can set base URI
        vm.prank(makeAddr("notAdmin"));
        vm.expectRevert();
        certificates.setBaseURI(newBaseURI);

        // Admin can set base URI
        vm.prank(admin);
        certificates.setBaseURI(newBaseURI);

        // Mint a token and verify the new base URI is used
        address alice = makeAddr("alice");
        vm.prank(admin);
        certificates.safeMint(alice, "collection_1");
        assertEq(certificates.tokenURI(1), string.concat(newBaseURI, "1"));
    }

    function test_setCollectionMetadata() public {
        bytes32 collection = "collection_1";
        string
            memory metadata = '{"name": "Test Collection", "description": "Test"}';

        // Only admin can set collection metadata
        vm.prank(makeAddr("notAdmin"));
        vm.expectRevert();
        certificates.setCollectionMetadata(collection, metadata);

        // Admin can set collection metadata
        vm.prank(admin);
        certificates.setCollectionMetadata(collection, metadata);

        // Verify metadata
        assertEq(certificates.getCollectionMetadata(collection), metadata);
    }

    function test_setTokenMetadata() public {
        address alice = makeAddr("alice");
        string
            memory metadata = '{"name": "Test Token", "description": "Test"}';

        // Mint a token first
        vm.prank(admin);
        certificates.safeMint(alice, "collection_1");

        // Only admin can set token metadata
        vm.prank(makeAddr("notAdmin"));
        vm.expectRevert();
        certificates.setTokenMetadata(1, metadata);

        // Admin can set token metadata
        vm.prank(admin);
        certificates.setTokenMetadata(1, metadata);

        // Verify metadata
        assertEq(certificates.getTokenMetadata(1), metadata);
    }

    function test_metadata_empty_by_default() public {
        bytes32 collection = "collection_1";
        address alice = makeAddr("alice");

        // Mint a token
        vm.prank(admin);
        certificates.safeMint(alice, collection);

        // Verify default empty metadata
        assertEq(certificates.getCollectionMetadata(collection), "");
        assertEq(certificates.getTokenMetadata(1), "");
    }
}
