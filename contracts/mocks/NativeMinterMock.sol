// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import { Test } from "@forge-std/Test.sol";

interface INativeMinter {
  function mintNativeCoin(address addr, uint256 amount) external;
}

contract NativeMinterMock is INativeMinter, Test {
  function mintNativeCoin(address account, uint256 amount) external {
    vm.deal(account, account.balance + amount);
  }
}
