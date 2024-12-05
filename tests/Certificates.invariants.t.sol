// SPDX-License-Identifier: Ecosystem

pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {Certificates} from "../contracts/tokens/Certificates.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts@5.0.2/proxy/ERC1967/ERC1967Proxy.sol";
import {console} from "forge-std/console.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";

contract Handler is Test {
    Certificates public certificates;
    address public admin;
    address[] public users;
    bytes32[] public collections;

    uint256 public constant LARGE_NUMBER = 1000;
    uint256 public constant NUM_USERS = 100;

    // Track minted tokens for verification
    mapping(address => mapping(bytes32 => uint256)) public userCollectionTokens;
    mapping(uint256 => bool) public tokenExists;
    uint256 public totalMinted;
    uint256 public totalBurned;

    // Add constructor
    constructor(Certificates _certificates) {
        certificates = _certificates;

        // Initialize users
        for (uint256 i = 0; i < NUM_USERS; i++) {
            users.push(makeAddr(string(abi.encodePacked("user", i))));
        }

        // Initialize some test collections
        for (uint256 i = 0; i < 10; i++) {
            collections.push(keccak256(abi.encodePacked("collection", i)));
        }
    }

    // Add a getter function for users length
    function getUsersLength() external view returns (uint256) {
        return users.length;
    }

    // Add a getter function for collections length
    function getCollectionsLength() external view returns (uint256) {
        return collections.length;
    }

    // Helper functions
    function randomUser() public returns (address) {
        return
            users[
                bound(
                    uint256(keccak256(abi.encodePacked(block.timestamp))),
                    0,
                    users.length - 1
                )
            ];
    }

    function randomCollection() public returns (bytes32) {
        return
            collections[
                bound(
                    uint256(keccak256(abi.encodePacked(block.timestamp))),
                    0,
                    collections.length - 1
                )
            ];
    }

    // Invariant test functions
    function mint(address to, bytes32 collection) public {
        if (to == address(0)) return; // Skip zero address
        if (userCollectionTokens[to][collection] != 0) return; // Skip if already minted

        try certificates.safeMint(to, collection) {
            uint256 tokenId = certificates.tokenByCollection(to, collection);
            userCollectionTokens[to][collection] = tokenId;
            tokenExists[tokenId] = true;
            totalMinted++;
        } catch {}
    }

    function burn(address user, bytes32 collection) public {
        if (userCollectionTokens[user][collection] == 0) return; // Skip if not minted

        try certificates.burnForUser(user, collection) {
            uint256 tokenId = userCollectionTokens[user][collection];
            delete userCollectionTokens[user][collection];
            tokenExists[tokenId] = false;
            totalBurned++;
        } catch {}
    }

    // Add a getter function for users array
    function getUser(uint256 index) external view returns (address) {
        return users[index];
    }
}

contract CertificateInvariants is StdInvariant, Test {
    Certificates public certificates;
    Handler public handler;
    address public admin;

    function setUp() public {
        console.log("Setting up certificates");
        Certificates certificatesImplementation = new Certificates();
        admin = makeAddr("admin");

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
        console.log("Certificates address:", address(certificates));

        // Initialize handler
        handler = new Handler(certificates);

        // Grant admin role to this test contract first
        vm.startPrank(admin);
        certificates.grantRole(
            certificates.DEFAULT_ADMIN_ROLE(),
            address(this)
        );

        // Now we can grant role to handler
        certificates.grantRole(
            certificates.DEFAULT_ADMIN_ROLE(),
            address(handler)
        );
        vm.stopPrank();

        // Setup roles
        bytes32 DEFAULT_ADMIN = certificates.DEFAULT_ADMIN_ROLE();
        certificates.grantRole(DEFAULT_ADMIN, address(handler));

        // Target handler for invariant testing
        targetContract(address(handler));

        // Explicitly exclude view functions from invariant testing
        excludeContract(address(this));
    }

    // Invariants
    function invariant_tokenIdNeverZero() public {
        for (uint256 i = 0; i < handler.getUsersLength(); i++) {
            for (uint256 j = 0; j < handler.getCollectionsLength(); j++) {
                uint256 tokenId = certificates.tokenByCollection(
                    handler.getUser(i),
                    handler.collections(j)
                );
                if (tokenId != 0) {
                    assert(handler.tokenExists(tokenId));
                }
            }
        }
    }

    function invariant_oneTokenPerCollectionPerUser() public {
        for (uint256 i = 0; i < handler.getUsersLength(); i++) {
            for (uint256 j = 0; j < handler.getCollectionsLength(); j++) {
                uint256 tokenId = certificates.tokenByCollection(
                    handler.getUser(i),
                    handler.collections(j)
                );
                if (tokenId != 0) {
                    assert(
                        handler.userCollectionTokens(
                            handler.getUser(i),
                            handler.collections(j)
                        ) == tokenId
                    );
                }
            }
        }
    }

    function invariant_burnedTokensStayBurned() public {
        for (uint256 i = 0; i < handler.getUsersLength(); i++) {
            for (uint256 j = 0; j < handler.getCollectionsLength(); j++) {
                uint256 tokenId = handler.userCollectionTokens(
                    handler.getUser(i),
                    handler.collections(j)
                );
                if (!handler.tokenExists(tokenId)) {
                    assert(
                        certificates.tokenByCollection(
                            handler.getUser(i),
                            handler.collections(j)
                        ) == 0
                    );
                }
            }
        }
    }

    function invariant_totalSupplyConsistent() public {
        assert(handler.totalMinted() >= handler.totalBurned());
    }
}
