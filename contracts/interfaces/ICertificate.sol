// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface ICertificate {
  function tokenByCollection(address account, bytes32 collection) external view returns (uint256);
}