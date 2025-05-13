// SPDX-License-Identifier: MIT

pragma solidity ^0.8.25;

import { AccessControlDefaultAdminRulesUpgradeable } from
  "@openzeppelin-contracts-upgradeable-5.3.0/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import { Initializable } from
  "@openzeppelin-contracts-upgradeable-5.3.0/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from
  "@openzeppelin-contracts-upgradeable-5.3.0/proxy/utils/UUPSUpgradeable.sol";
import { ERC721EnumerableUpgradeable } from
  "@openzeppelin-contracts-upgradeable-5.3.0/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import { EnumerableSet } from "@openzeppelin-contracts-5.3.0/utils/structs/EnumerableSet.sol";


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
  uint48 defaultAdminDelay;
}

contract NodeLicense is
  Initializable,
  ERC721EnumerableUpgradeable,
  AccessControlDefaultAdminRulesUpgradeable,
  UUPSUpgradeable
{
  using EnumerableSet for EnumerableSet.AddressSet;

  bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

  string private _baseTokenURI;
  uint256 private _nextTokenId;
  uint32 private _lockedUntil;
  address private _nftStakingManager;

  mapping(uint256 tokenId => address) private _tokenDelegateApprovals;
  mapping(address => EnumerableSet.AddressSet) private _delegateOperatorApprovals;

  event BaseURIUpdated(string newBaseURI);
  event NFTStakingManagerUpdated(address indexed oldManager, address indexed newManager);
  event UnlockTimeUpdated(uint32 newUnlockTime);
  event DelegateApproval(address indexed owner, address indexed approved, uint256 indexed tokenId);
  event DelegateApprovalForAll(address indexed owner, address indexed operator, bool approved);

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

  function initialize(NodeLicenseSettings memory settings) public initializer {
    __ERC721_init(settings.name, settings.symbol);
    __AccessControl_init();
    __UUPSUpgradeable_init();
    __AccessControlDefaultAdminRules_init(settings.defaultAdminDelay, settings.admin);

    _nextTokenId = 1;
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

  function approveDelegation(address to, uint256 tokenId) public {
    _approveDelegation(to, tokenId, _msgSender());
  }

  function _approveDelegation(address to, uint256 tokenId, address auth) internal {
    if (auth != address(0)) {
      address owner = _requireOwned(tokenId);

      if (auth != address(0) && owner != auth && !isApprovedForAll(owner, auth)) {
        revert ERC721InvalidApprover(auth);
      }

      emit DelegateApproval(owner, to, tokenId);
    }

    _tokenDelegateApprovals[tokenId] = to;
  }

  function setDelegationApprovalForAll(address operator, bool approved) public {
    _setDelegationApprovalForAll(_msgSender(), operator, approved);
  }

  function _setDelegationApprovalForAll(address owner, address operator, bool approved) internal {
    if (operator == address(0)) {
      revert ERC721InvalidOperator(operator);
    }

    if (approved) {
      _delegateOperatorApprovals[owner].add(operator);
    } else {
      _delegateOperatorApprovals[owner].remove(operator);
    }

    emit DelegateApprovalForAll(owner, operator, approved);
  }

  function isDelegationApprovedForAll(address owner, address operator) public view returns (bool) {
    return _delegateOperatorApprovals[owner].contains(operator);
  }

  function getDelegationApproval(uint256 tokenId) public view returns (address) {
    _requireOwned(tokenId);
    return _tokenDelegateApprovals[tokenId];
  }

  function setBaseURI(string memory baseTokenURI) public onlyRole(DEFAULT_ADMIN_ROLE) {
    emit BaseURIUpdated(baseTokenURI);
    _baseTokenURI = baseTokenURI;
  }

  function setNFTStakingManager(address nftStakingManager) public onlyRole(DEFAULT_ADMIN_ROLE) {
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
    
    // Clear approvals
    _approveDelegation(address(0), tokenId, address(0));

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
    override (ERC721EnumerableUpgradeable, AccessControlDefaultAdminRulesUpgradeable)
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

  function getDelegateOperatorsForOwner(address owner) external view returns (address[] memory) {
    return _delegateOperatorApprovals[owner].values();
  }
}
