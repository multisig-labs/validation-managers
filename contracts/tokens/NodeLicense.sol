// SPDX-License-Identifier: MIT

pragma solidity ^0.8.25;

import { AccessControlDefaultAdminRulesUpgradeable } from
  "@openzeppelin-contracts-upgradeable-5.2.0/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import { Initializable } from
  "@openzeppelin-contracts-upgradeable-5.2.0/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from
  "@openzeppelin-contracts-upgradeable-5.2.0/proxy/utils/UUPSUpgradeable.sol";
import { ERC721Upgradeable } from
  "@openzeppelin-contracts-upgradeable-5.2.0/token/ERC721/ERC721Upgradeable.sol";

interface INFTStakingManager {
  function isTokenDelegated(uint256 tokenId) external view returns (bool);
}

/* 
 * @title NodeLicense
 * @notice An ERC721 NFT that represents a license that can be delegated to a Validator node
 * whos staking is managed by the NFT Staking Manager contract.
 * 
 * @param defaultAdmin The address of the default admin role.
 * @param minter The address of the minter role.
 * @param nftStakingManager The address of the NFTStakingManager contract.
 * @param name The name of the token.
 * @param symbol The symbol of the token.
 * @param baseTokenURI The base URI of the token.
 * @param unlockTime (optional) The timestamp when the license will be unlocked.
 *
 * Transfers are blocked until the unlockTime and also if the token is staked to an NFTStakingManager.
 * 
 * Implements ERC721Metadata such that `tokenURI(uint256 _tokenId)` returns the baseTokenURI + _tokenId,
 * and can point to a metadata JSON file with the following structure:
 *
 * {
 *     "title": "Asset Metadata",
 *     "type": "object",
 *     "properties": {
 *         "name": {
 *             "type": "string",
 *             "description": "Identifies the asset to which this NFT represents"
 *         },
 *         "description": {
 *             "type": "string",
 *             "description": "Describes the asset to which this NFT represents"
 *         },
 *         "image": {
 *             "type": "string",
 *             "description": "A URI pointing to a resource with mime type image/* representing the asset to which this NFT represents. Consider making any images at a width between 320 and 1080 pixels and aspect ratio between 1.91:1 and 4:5 inclusive."
 *         }
 *     }
 * } 
 */
 
 struct NodeLicenseSettings {
  address admin;
  address minter;
  address nftStakingManager;
  string name;
  string symbol;
  string baseTokenURI;
  uint32 unlockTime;
 }

contract NodeLicense is
  Initializable,
  ERC721Upgradeable,
  AccessControlDefaultAdminRulesUpgradeable,
  UUPSUpgradeable
{
  bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

  string private _baseTokenURI;
  uint256 private _nextTokenId;
  uint32 private _lockedUntil;
  address private _nftStakingManager;

  error ArrayLengthMismatch();
  error ArrayLengthZero();
  error LicenseLockedError(uint32 unlockTime);
  error LicenseStakedError();
  error NoTokensToMint();
  error ZeroAddress();

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }
  

  function initialize(
    NodeLicenseSettings memory settings
  ) public initializer {
    __ERC721_init(settings.name, settings.symbol);
    __AccessControl_init();
    __UUPSUpgradeable_init();

    _nextTokenId = 1;
    _grantRole(DEFAULT_ADMIN_ROLE, settings.admin);
    _grantRole(MINTER_ROLE, settings.minter);
    _baseTokenURI = settings.baseTokenURI;
    _lockedUntil = settings.unlockTime;
    _nftStakingManager = settings.nftStakingManager;
  }

  function mint(address to) public onlyRole(MINTER_ROLE) returns (uint256) {
    if (to == address(0)) revert ZeroAddress();
    uint256 tokenId = _nextTokenId++;
    _safeMint(to, tokenId);
    return tokenId;
  }

  function batchMint(address[] calldata recipients, uint256[] calldata amounts)
    public
    onlyRole(MINTER_ROLE)
  {
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

  function _update(address to, uint256 tokenId, address auth)
    internal
    virtual
    override
    returns (address)
  {
    // If both addresses are non-zero, it's a transfer (not a mint or burn)
    if (
      auth != address(0) && to != address(0) && _lockedUntil > 0 && block.timestamp < _lockedUntil
    ) {
      // Only check timelock for transfers
      revert LicenseLockedError(_lockedUntil);
    }

    // If token is staked to NFT Staking Manager, disallow transfer
    if (
      _nftStakingManager != address(0)
        && INFTStakingManager(_nftStakingManager).isTokenDelegated(tokenId)
    ) {
      revert LicenseStakedError();
    }

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

  function supportsInterface(bytes4 interfaceId)
    public
    view
    override (ERC721Upgradeable, AccessControlDefaultAdminRulesUpgradeable)
    returns (bool)
  {
    return super.supportsInterface(interfaceId);
  }
}
