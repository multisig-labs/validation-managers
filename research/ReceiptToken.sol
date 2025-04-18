// SPDX-License-Identifier: MIT

pragma solidity ^0.8.25;

import { AccessControlDefaultAdminRulesUpgradeable } from
  "@openzeppelin-contracts-upgradeable-5.3.0/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import { Initializable } from
  "@openzeppelin-contracts-upgradeable-5.3.0/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from
  "@openzeppelin-contracts-upgradeable-5.3.0/proxy/utils/UUPSUpgradeable.sol";
import { ERC721Upgradeable } from
  "@openzeppelin-contracts-upgradeable-5.3.0/token/ERC721/ERC721Upgradeable.sol";
import { ERC721BurnableUpgradeable } from
  "@openzeppelin-contracts-upgradeable-5.3.0/token/ERC721/extensions/ERC721BurnableUpgradeable.sol";

// Sketch of a generic Receipt, tying a user to, for example, all their licenses in a vault.
// This is a soulbound token, meaning it cannot be transferred.
// It can be burned when the user leaves the vault.

contract ReceiptToken is
  Initializable,
  ERC721Upgradeable,
  ERC721BurnableUpgradeable,
  AccessControlDefaultAdminRulesUpgradeable,
  UUPSUpgradeable
{
  bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

  string private _baseTokenURI;
  uint256 private _nextTokenId;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize(
    address defaultAdmin,
    address minter,
    string calldata name,
    string calldata symbol,
    string calldata baseTokenURI
  ) public initializer {
    __ERC721_init(name, symbol);
    __AccessControl_init();
    __UUPSUpgradeable_init();

    _nextTokenId = 1;
    _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
    _grantRole(MINTER_ROLE, minter);
    _baseTokenURI = baseTokenURI;
  }

  function mint(address to) public onlyRole(MINTER_ROLE) returns (uint256) {
    uint256 tokenId = _nextTokenId++;
    _safeMint(to, tokenId);
    return tokenId;
  }

  function burn(uint256 tokenId) public override onlyRole(MINTER_ROLE) {
    _burn(tokenId);
  }

  function setBaseURI(string memory baseTokenURI) public onlyRole(DEFAULT_ADMIN_ROLE) {
    _baseTokenURI = baseTokenURI;
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

  function _authorizeUpgrade(address newImplementation)
    internal
    override
    onlyRole(DEFAULT_ADMIN_ROLE)
  { }

  function _baseURI() internal view override returns (string memory) {
    return _baseTokenURI;
  }

  // The following functions are overrides required by Solidity.

  function supportsInterface(bytes4 interfaceId)
    public
    view
    override (ERC721Upgradeable, AccessControlDefaultAdminRulesUpgradeable)
    returns (bool)
  {
    return super.supportsInterface(interfaceId);
  }
}
