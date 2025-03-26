// SPDX-License-Identifier: MIT

pragma solidity ^0.8.25;

import {AccessControlUpgradeable} from "@openzeppelin-contracts-upgradeable-5.2.0/access/AccessControlUpgradeable.sol";
import {Initializable} from "@openzeppelin-contracts-upgradeable-5.2.0/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin-contracts-upgradeable-5.2.0/proxy/utils/UUPSUpgradeable.sol";

import {IERC20} from "@openzeppelin-contracts-5.2.0/token/ERC20/IERC20.sol";
import {ERC721Upgradeable} from "@openzeppelin-contracts-upgradeable-5.2.0/token/ERC721/ERC721Upgradeable.sol";

import {ERC721UpgradeableBatchable} from "./ERC721UpgradeableBatchable.sol";

contract EthixLicense is Initializable, ERC721UpgradeableBatchable, AccessControlUpgradeable, UUPSUpgradeable {
  bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
  bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

  string private _baseTokenURI;
  uint256 private _nextTokenId;
  uint32 private _lockedUntil;

  event BatchMinted(address indexed minter, address[] recipients, uint256[] tokenIds);

  error ArrayLengthMismatch();
  error ArrayLengthZero();
  error LicenseLockedError(uint32 unlockTime);
  error NoTokensToMint();
  error ZeroAddress();

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
    // _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
    _grantRole(MINTER_ROLE, minter);
    _grantRole(UPGRADER_ROLE, upgrader);
    _baseTokenURI = baseTokenURI;
    _lockedUntil = unlockTime;
  }

  function mint(address to) public onlyRole(MINTER_ROLE) returns (uint256) {
    if (to == address(0)) revert ZeroAddress();
    uint256 tokenId = _nextTokenId++;
    _safeMint(to, tokenId);
    return tokenId;
  }

  function batchMint(address[] calldata recipients, uint256[] calldata amounts) public onlyRole(MINTER_ROLE) {
    if (recipients.length == 0) revert ArrayLengthZero();
    if (recipients.length != amounts.length) revert ArrayLengthMismatch();

    uint256 totalAmount;
    for (uint256 i = 0; i < amounts.length; i++) {
      totalAmount += amounts[i];
    }

    if (totalAmount == 0) revert NoTokensToMint();

    uint256[] memory tokenIds = new uint256[](totalAmount);
    uint256 startingTokenId = _nextTokenId;
    _nextTokenId += totalAmount;

    uint256 currentIndex;
    for (uint256 i = 0; i < recipients.length; i++) {
      for (uint256 j = 0; j < amounts[i]; j++) {
        uint256 tokenId = startingTokenId + currentIndex;
        tokenIds[currentIndex] = tokenId;
        _safeMint(recipients[i], tokenId);
        currentIndex++;
      }
    }
    emit BatchMinted(msg.sender, recipients, tokenIds);
  }

  function batchTransferFrom(address from, address to, uint256[] memory tokenIds) public {
    for (uint256 i = 0; i < tokenIds.length; i++) {
      transferFrom(from, to, tokenIds[i]);
    }
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

  function rescueERC20(address token) external onlyRole(DEFAULT_ADMIN_ROLE) {
    IERC20(token).transferFrom(address(this), msg.sender, IERC20(token).balanceOf(address(this)));
  }

  function rescueETH(uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
    if (amount > address(this).balance) revert("Insufficient balance");
    (bool success,) = payable(msg.sender).call{value: amount}("");
    require(success, "ETH transfer failed");
  }

  // The following functions are overrides required by Solidity.

  function supportsInterface(bytes4 interfaceId) public view override (ERC721Upgradeable, AccessControlUpgradeable) returns (bool) {
    return super.supportsInterface(interfaceId);
  }
}
