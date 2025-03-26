// SPDX-License-Identifier: MIT

pragma solidity ^0.8.25;

import {ERC721Upgradeable} from "@openzeppelin-contracts-upgradeable-5.2.0/token/ERC721/ERC721Upgradeable.sol";

abstract contract ERC721UpgradeableBatchable is ERC721Upgradeable {

  function safeBatchTransferFrom(address from, address to, uint256[] memory tokenIds) public {
    for (uint256 i = 0; i < tokenIds.length; i++) {
      safeTransferFrom(from, to, tokenIds[i]);
    }
  }
}
