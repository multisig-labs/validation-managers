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

/* 
 * @title HardwareOperatorLicense
 * @notice An ERC721 Soulbound NFT that represents a license that can be staked to create a Validator node
 * whos staking is managed by the NFTStakingManager contract.
 * 
 * @param defaultAdmin The address of the default admin role.
 * @param minter The address of the minter role.
 * @param name The name of the token.
 * @param symbol The symbol of the token.
 * @param baseTokenURI The base URI of the token.
 *
 * Transfers are never allowed.
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
contract HardwareOperatorLicense is
  Initializable,
  ERC721Upgradeable,
  AccessControlDefaultAdminRulesUpgradeable,
  UUPSUpgradeable
{
  bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

  string private _baseTokenURI;
  uint256 private _nextTokenId;

  error ZeroAddress();

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

    _baseTokenURI = baseTokenURI;
    _nextTokenId = 1;
    _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
    _grantRole(MINTER_ROLE, minter);
  }

  function mint(address to) public onlyRole(MINTER_ROLE) returns (uint256) {
    if (to == address(0)) revert ZeroAddress();
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

  function _baseURI() internal view override returns (string memory) {
    return _baseTokenURI;
  }

  function _authorizeUpgrade(address newImplementation)
    internal
    override
    onlyRole(DEFAULT_ADMIN_ROLE)
  { }

  function supportsInterface(bytes4 interfaceId)
    public
    view
    override (ERC721Upgradeable, AccessControlDefaultAdminRulesUpgradeable)
    returns (bool)
  {
    return super.supportsInterface(interfaceId);
  }
}
