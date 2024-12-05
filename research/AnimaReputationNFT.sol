// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract AnimaReputation is Initializable, ERC721Upgradeable, AccessControlUpgradeable, UUPSUpgradeable {
    using Strings for uint256;

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    uint256 private _nextTokenId;
    mapping(bytes32 => mapping(address => uint256)) private _collectionToAddressToToken;
    string private _baseTokenURI;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address defaultAdmin, address minter, address upgrader, string memory baseTokenURI)
    initializer public
    {
        __ERC721_init("Anima Reputation", "AR");
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _nextTokenId = 1;
        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(MINTER_ROLE, minter);
        _grantRole(UPGRADER_ROLE, upgrader);
        _baseTokenURI = baseTokenURI;
    }

    function setBaseURI(string memory baseTokenURI) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _baseTokenURI = baseTokenURI;
    }

    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }

    function mainTokenByCollection(address account, bytes32 collection) public view returns (uint256) {
        return _collectionToAddressToToken[collection][account];
    }

    function safeMint(address to, bytes32 collection) public onlyRole(MINTER_ROLE) {
        require(_collectionToAddressToToken[collection][to] == 0, "This collection already has a token for this address.");

        uint256 tokenId = _nextTokenId++;
        _safeMint(to, tokenId);
        _collectionToAddressToToken[collection][to] = tokenId;
    }

    function burnForUser(address account, bytes32 collection) public onlyRole(MINTER_ROLE) {
        uint256 tokenId = _collectionToAddressToToken[collection][account];
        _burn(tokenId);
        delete _collectionToAddressToToken[collection][account];
    }

    function _update(address to, uint256 tokenId, address auth) internal virtual override returns (address) {
        require(auth == address(0) || to == address(0), "This a Soulbound token. It cannot be transferred.");
        return super._update(to, tokenId, auth);
    }
    function _authorizeUpgrade(address newImplementation)
    internal
    onlyRole(UPGRADER_ROLE)
    override
    {}

    // The following functions are overrides required by Solidity.

    function supportsInterface(bytes4 interfaceId)
    public
    view
    override(ERC721Upgradeable, AccessControlUpgradeable)
    returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
