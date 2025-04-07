// SPDX-License-Identifier: MIT

pragma solidity ^0.8.25;

import { AccessControlDefaultAdminRulesUpgradeable } from
  "@openzeppelin-contracts-upgradeable-5.2.0/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import { Initializable } from
  "@openzeppelin-contracts-upgradeable-5.2.0/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from
  "@openzeppelin-contracts-upgradeable-5.2.0/proxy/utils/UUPSUpgradeable.sol";

import { IERC20 } from "@openzeppelin-contracts-5.2.0/token/ERC20/IERC20.sol";
import { ERC721Upgradeable } from
  "@openzeppelin-contracts-upgradeable-5.2.0/token/ERC721/ERC721Upgradeable.sol";

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

  // These functions allow the admin to rescue any tokens that were accidentally sent to this contract.

  function rescueERC20(address token) external onlyRole(DEFAULT_ADMIN_ROLE) {
    IERC20(token).transferFrom(address(this), msg.sender, IERC20(token).balanceOf(address(this)));
  }

  function rescueETH(uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
    if (amount > address(this).balance) revert("Insufficient balance");
    (bool success,) = payable(msg.sender).call{ value: amount }("");
    require(success, "ETH transfer failed");
  }

  // The following functions are overrides required by Solidity.

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
