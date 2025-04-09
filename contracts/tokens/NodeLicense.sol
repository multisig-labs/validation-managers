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
  function getTokenLockedBy(uint256 tokenId) external view returns (bytes32);
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
  uint256 maxBatchSize;
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
  uint256 public _maxBatchSize;

  error ArrayLengthMismatch();
  error ArrayLengthZero();
  error LicenseLockedError(uint32 unlockTime);
  error LicenseStakedError();
  error NoTokensToMint();
  error ZeroAddress();
  error BatchSizeTooLarge();

  event NFTStakingManagerUpdated(address indexed oldManager, address indexed newManager);
  event BaseURIUpdated(string newBaseURI);
  event UnlockTimeUpdated(uint32 newUnlockTime);

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize(NodeLicenseSettings memory settings) public initializer {
    __ERC721_init(settings.name, settings.symbol);
    __AccessControl_init();
    __UUPSUpgradeable_init();

    _nextTokenId = 1;
    _grantRole(DEFAULT_ADMIN_ROLE, settings.admin);
    _grantRole(MINTER_ROLE, settings.minter);
    _baseTokenURI = settings.baseTokenURI;
    _lockedUntil = settings.unlockTime;
    _nftStakingManager = settings.nftStakingManager;
    _maxBatchSize = settings.maxBatchSize;
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
    if (recipients.length > _maxBatchSize) revert BatchSizeTooLarge();

    uint256 totalAmount;
    for (uint256 i = 0; i < amounts.length; i++) {
      totalAmount += amounts[i];
    }

    if (totalAmount == 0) revert NoTokensToMint();

    uint256 currentTokenId = _nextTokenId;
    _nextTokenId += totalAmount;

    for (uint256 i = 0; i < recipients.length; i++) {
      if (recipients[i] == address(0)) revert ZeroAddress();
      for (uint256 j = 0; j < amounts[i]; j++) {
        _safeMint(recipients[i], currentTokenId);
        currentTokenId++;
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
    emit BaseURIUpdated(baseTokenURI);
    _baseTokenURI = baseTokenURI;
  }

  function setNFTStakingManager(address nftStakingManager) public onlyRole(DEFAULT_ADMIN_ROLE) {
    if (nftStakingManager == address(0)) revert ZeroAddress();
    emit NFTStakingManagerUpdated(_nftStakingManager, nftStakingManager);
    _nftStakingManager = nftStakingManager;
  }

  function setUnlockTime(uint32 newUnlockTime) public onlyRole(DEFAULT_ADMIN_ROLE) {
    emit UnlockTimeUpdated(newUnlockTime);
    _lockedUntil = newUnlockTime;
  }

  function _update(address to, uint256 tokenId, address auth)
    internal
    virtual
    override
    returns (address)
  {
    // Early return for mint/burn operations
    if (auth == address(0) || to == address(0)) {
      return super._update(to, tokenId, auth);
    }

    // Check timelock for transfers
    if (_lockedUntil > 0 && block.timestamp < _lockedUntil) {
      revert LicenseLockedError(_lockedUntil);
    }

    // Check staking lock
    if (_nftStakingManager != address(0)) {
      bytes32 lockId = INFTStakingManager(_nftStakingManager).getTokenLockedBy(tokenId);
      if (lockId != bytes32(0)) {
        revert LicenseStakedError();
      }
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

  function getNFTStakingManager() external view returns (address) {
    return _nftStakingManager;
  }

  function getUnlockTime() external view returns (uint32) {
    return _lockedUntil;
  }
}
