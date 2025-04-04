// (c) 2023, Ava Labs, Inc. All rights reserved.
// See the file LICENSE for licensing terms.

// SPDX-License-Identifier: Ecosystem

pragma solidity 0.8.25;

/**
 * THIS IS AN EXAMPLE CONTRACT THAT USES UN-AUDITED CODE.
 * DO NOT USE THIS CODE IN PRODUCTION.
 */
import {IERC20Mintable} from "@avalabs/icm-contracts/validator-manager/interfaces/IERC20Mintable.sol";
import {ERC20, ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

contract ExampleERC20 is ERC20Burnable, IERC20Mintable {
  string private constant _TOKEN_NAME = "Mock Token";
  string private constant _TOKEN_SYMBOL = "EXMP";

  uint256 private constant _MAX_MINT = 1e19;

  constructor() ERC20(_TOKEN_NAME, _TOKEN_SYMBOL) {
    _mint(msg.sender, 1e28);
  }

  function mint(uint256 amount) external {
    // Can only mint 10 at a time.
    require(amount <= _MAX_MINT, "ExampleERC20: max mint exceeded");

    _mint(msg.sender, amount);
  }

  function mint(address account, uint256 amount) external {
    // Can only mint 10 at a time.
    require(amount <= _MAX_MINT, "ExampleERC20: max mint exceeded");

    _mint(account, amount);
  }
}
