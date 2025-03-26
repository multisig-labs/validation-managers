
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.25;

import {IERC721} from "@openzeppelin-contracts-5.2.0/token/ERC721/IERC721.sol";

interface IERC721Batchable is IERC721 {
  function safeBatchTransferFrom(address from, address to, uint256[] memory tokenIds) external;
}
