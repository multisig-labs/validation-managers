// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

import { ERC721 } from "@openzeppelin-contracts-5.3.0/token/ERC721/ERC721.sol";

contract ERC721Mock is ERC721 {
  uint256 private _nextTokenId = 0;

  constructor(string memory name, string memory symbol) ERC721(name, symbol) { }

  function mint(address to) public returns (uint256) {
    uint256 tokenId = _nextTokenId++;
    _mint(to, tokenId);
    return tokenId;
  }

  function batchMint(address to, uint256 numTokens) public returns (uint256[] memory) {
    uint256[] memory tokenIds = new uint256[](numTokens);
    for (uint256 i = 0; i < numTokens; i++) {
      tokenIds[i] = mint(to);
    }
    return tokenIds;
  }

  function totalSupply() public view returns (uint256) {
    return _nextTokenId;
  }
}
