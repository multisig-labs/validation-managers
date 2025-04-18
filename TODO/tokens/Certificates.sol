// SPDX-License-Identifier: MIT

pragma solidity ^0.8.25;

import { AccessControlUpgradeable } from
  "@openzeppelin-5.2.0/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { Initializable } from
  "@openzeppelin-contracts-upgradeable-5.3.0/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from
  "@openzeppelin-contracts-upgradeable-5.3.0/proxy/utils/UUPSUpgradeable.sol";
import { ERC721Upgradeable } from
  "@openzeppelin-contracts-upgradeable-5.3.0/token/ERC721/ERC721Upgradeable.sol";

// @notice A contract for issuing certificates to users, supports multiple collections, which can be used for different purposes (KYC, etc).
// i.e. certificates.mint(nodeOwner, keccak256("KYC-Fractal.com"));
// Then check it with certificates.tokenByCollection(nodeOwner, keccak256("KYC-Fractal.com"))
// @dev This is a Soulbound token, meaning it cannot be transferred.
// @dev This contract is upgradable.

contract Certificates is
  Initializable,
  ERC721Upgradeable,
  AccessControlUpgradeable,
  UUPSUpgradeable
{
  bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
  bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

  uint256 private _nextTokenId;
  // Collection (keccak256(collectionName)) to address to tokenId
  mapping(bytes32 => mapping(address => uint256)) private _collectionToAddressToToken;
  // Collection (keccak256(collectionName)) to metadata (JSON)
  mapping(bytes32 => string) private _collectionToMetadata;
  // Token to metadata (JSON)
  mapping(uint256 => string) private _tokenToMetadata;

  string private _baseTokenURI;

  function initialize(
    address defaultAdmin,
    address minter,
    address upgrader,
    string memory baseTokenURI
  ) public initializer {
    __ERC721_init("Certificates", "CERT");
    __AccessControl_init();
    __UUPSUpgradeable_init();

    _nextTokenId = 1;
    _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
    _grantRole(MINTER_ROLE, minter);
    _grantRole(UPGRADER_ROLE, upgrader);
    _baseTokenURI = baseTokenURI;
  }

  function tokenByCollection(address account, bytes32 collection) public view returns (uint256) {
    return _collectionToAddressToToken[collection][account];
  }

  function mint(address to, bytes32 collection) public onlyRole(MINTER_ROLE) {
    require(
      _collectionToAddressToToken[collection][to] == 0,
      "This collection already has a token for this address."
    );

    uint256 tokenId = _nextTokenId++;
    _safeMint(to, tokenId);
    _collectionToAddressToToken[collection][to] = tokenId;
  }

  function burnForUser(address account, bytes32 collection) public onlyRole(MINTER_ROLE) {
    uint256 tokenId = _collectionToAddressToToken[collection][account];
    _burn(tokenId);
    delete _collectionToAddressToToken[collection][account];
  }

  function burnForCollection(bytes32 collection) public {
    uint256 tokenId = _collectionToAddressToToken[collection][_msgSender()];
    require(tokenId != 0, "No token for this collection for this address.");
    _burn(tokenId);
    delete _collectionToAddressToToken[collection][_msgSender()];
  }

  function _update(address to, uint256 tokenId, address auth)
    internal
    virtual
    override
    returns (address)
  {
    require(
      auth == address(0) || to == address(0), "This a Soulbound token. It cannot be transferred."
    );
    return super._update(to, tokenId, auth);
  }

  function setBaseURI(string memory baseTokenURI) public onlyRole(DEFAULT_ADMIN_ROLE) {
    _baseTokenURI = baseTokenURI;
  }

  function _baseURI() internal view override returns (string memory) {
    return _baseTokenURI;
  }

  function setCollectionMetadata(bytes32 collection, string memory metadata)
    public
    onlyRole(DEFAULT_ADMIN_ROLE)
  {
    _collectionToMetadata[collection] = metadata;
  }

  function getCollectionMetadata(bytes32 collection) public view returns (string memory) {
    return _collectionToMetadata[collection];
  }

  function setTokenMetadata(uint256 tokenId, string memory metadata)
    public
    onlyRole(DEFAULT_ADMIN_ROLE)
  {
    _tokenToMetadata[tokenId] = metadata;
  }

  function getTokenMetadata(uint256 tokenId) public view returns (string memory) {
    return _tokenToMetadata[tokenId];
  }

  function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) { }

  // The following functions are overrides required by Solidity.

  function supportsInterface(bytes4 interfaceId)
    public
    view
    override (ERC721Upgradeable, AccessControlUpgradeable)
    returns (bool)
  {
    return super.supportsInterface(interfaceId);
  }
}
