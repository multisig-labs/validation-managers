// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

import { ERC721 } from "@openzeppelin-contracts-5.2.0/token/ERC721/ERC721.sol";

contract ERC721Mock is ERC721 {
  constructor(string memory name, string memory symbol) ERC721(name, symbol) { }

  function mint(address to, uint256 tokenId) public {
    _mint(to, tokenId);
  }

  function batchMint(address to, uint256 numTokens) public returns (uint256[] memory) {
    uint256[] memory tokenIds = new uint256[](numTokens);
    for (uint256 i = 0; i < numTokens; i++) {
      _mint(to, i);
      tokenIds[i] = i;
    }
    return tokenIds;
  }
}
