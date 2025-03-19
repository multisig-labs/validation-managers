// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

import {ERC721} from "@openzeppelin-contracts-5.2.0/token/ERC721/ERC721.sol";

contract ERC721Mock is ERC721 {
  constructor(string memory name, string memory symbol) ERC721(name, symbol) {}

  function mint(address to, uint256 tokenId) public {
    _mint(to, tokenId);
  }
}
