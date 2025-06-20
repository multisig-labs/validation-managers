// SPDX-License-Identifier: MIT

pragma solidity ^0.8.25;

import { NodeLicense, NodeLicenseSettings } from "./NodeLicense.sol";

/**
 * @title UniformNodeLicense
 * @notice A specialized NodeLicense where all tokens have identical metadata
 * @dev Overrides tokenURI to return the same URI for all tokens, useful for
 *      tokens where visual differences don't matter
 */
contract UniformNodeLicense is NodeLicense {
  /**
   * @dev Returns the same URI for all tokens instead of baseURI + tokenId
   * @param tokenId The token ID (must exist)
   * @return The uniform metadata URI for all tokens
   */
  function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
    _requireOwned(tokenId);
    return _baseURI();
  }
}
