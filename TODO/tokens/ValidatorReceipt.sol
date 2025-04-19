// SPDX-License-Identifier: MIT

pragma solidity ^0.8.25;

import { AccessControlUpgradeable } from
  "@openzeppelin-contracts-upgradeable-5.3.0/access/AccessControlUpgradeable.sol";
import { Initializable } from
  "@openzeppelin-contracts-upgradeable-5.3.0/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from
  "@openzeppelin-contracts-upgradeable-5.3.0/proxy/utils/UUPSUpgradeable.sol";
import { ERC721Upgradeable } from
  "@openzeppelin-contracts-upgradeable-5.3.0/token/ERC721/ERC721Upgradeable.sol";

contract ValidatorReceipt is
  Initializable,
  ERC721Upgradeable,
  AccessControlUpgradeable,
  UUPSUpgradeable
{
  bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
  bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

  uint256 private _nextTokenId;
  string private _baseTokenURI;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize(
    address defaultAdmin,
    address minter,
    address upgrader,
    string memory baseTokenURI
  ) public initializer {
    __ERC721_init("ValidatorReceipt", "VRCT");
    __AccessControl_init();
    __UUPSUpgradeable_init();

    _nextTokenId = 1;
    _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
    _grantRole(MINTER_ROLE, minter);
    _grantRole(UPGRADER_ROLE, upgrader);
    _baseTokenURI = baseTokenURI;
  }

  function mint(address to) public onlyRole(MINTER_ROLE) returns (uint256) {
    uint256 tokenId = _nextTokenId++;
    _safeMint(to, tokenId);
    return tokenId;
  }

  function burn(uint256 tokenId) public onlyRole(MINTER_ROLE) {
    _burn(tokenId);
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
