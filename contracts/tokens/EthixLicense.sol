// SPDX-License-Identifier: MIT

pragma solidity ^0.8.25;

import {AccessControlUpgradeable} from "@openzeppelin-contracts-upgradeable-5.2.0/access/AccessControlUpgradeable.sol";
import {Initializable} from "@openzeppelin-contracts-upgradeable-5.2.0/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin-contracts-upgradeable-5.2.0/proxy/utils/UUPSUpgradeable.sol";
import {ERC721Upgradeable} from "@openzeppelin-contracts-upgradeable-5.2.0/token/ERC721/ERC721Upgradeable.sol";

contract EthixLicense is Initializable, ERC721Upgradeable, AccessControlUpgradeable, UUPSUpgradeable {
  bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
  bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

  string private _baseTokenURI;
  uint256 private _nextTokenId;
  uint32 private _lockedUntil;

  error LicenseLockedError(uint32 unlockTime);

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize(
    address defaultAdmin,
    address minter,
    address upgrader,
    uint32 unlockTime,
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
    _grantRole(UPGRADER_ROLE, upgrader);
    _baseTokenURI = baseTokenURI;
    _lockedUntil = unlockTime;
  }

  function mint(address to) public onlyRole(MINTER_ROLE) returns (uint256) {
    uint256 tokenId = _nextTokenId++;
    _safeMint(to, tokenId);
    return tokenId;
  }

  function burn(uint256 tokenId) public onlyRole(MINTER_ROLE) {
    _burn(tokenId);
  }

  function setBaseURI(string memory baseTokenURI) public onlyRole(DEFAULT_ADMIN_ROLE) {
    _baseTokenURI = baseTokenURI;
  }

  function _update(address to, uint256 tokenId, address auth) internal virtual override returns (address) {
    // If both addresses are non-zero, it's a transfer (not a mint or burn)
    if (auth != address(0) && to != address(0) && block.timestamp < _lockedUntil) {
      // Only check timelock for transfers
      revert LicenseLockedError(_lockedUntil);
    }
    return super._update(to, tokenId, auth);
  }

  function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}

  function _baseURI() internal view override returns (string memory) {
    return _baseTokenURI;
  }

  // The following functions are overrides required by Solidity.

  function supportsInterface(bytes4 interfaceId) public view override (ERC721Upgradeable, AccessControlUpgradeable) returns (bool) {
    return super.supportsInterface(interfaceId);
  }
}
