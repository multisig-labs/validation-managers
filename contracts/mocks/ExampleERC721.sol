// SPDX-License-Identifier: Ecosystem

pragma solidity 0.8.25;

import {ERC721} from "@openzeppelin/contracts@5.0.2/token/ERC721/ERC721.sol";

contract ExampleERC721 is ERC721 {
  string private constant _TOKEN_NAME = "Mock NFT";
  string private constant _TOKEN_SYMBOL = "EXMP";

  uint256 private _tokenIdCounter;
  uint256 private constant _MAX_MINT = 10000;

  constructor() ERC721(_TOKEN_NAME, _TOKEN_SYMBOL) {}

  function mint() external {
    require(_tokenIdCounter < _MAX_MINT, "ExampleERC721: max supply reached");
    _tokenIdCounter++;
    _safeMint(msg.sender, _tokenIdCounter);
  }

  function mint(
    address to
  ) external {
    require(_tokenIdCounter < _MAX_MINT, "ExampleERC721: max supply reached");
    _tokenIdCounter++;
    _safeMint(to, _tokenIdCounter);
  }
}
