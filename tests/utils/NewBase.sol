// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

abstract contract NewBase {
  uint256 private randNonce = 0;
  uint160 private actorCounter = 0;

  function getActor(string memory name) public returns (address) {
    actorCounter++;
    address addr = address(uint160(0x10000 + actorCounter));
    return addr;
  }
}
