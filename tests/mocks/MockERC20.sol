// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    uint8 private _decimals;
    bool private _transferShouldFail;

    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals_
    ) ERC20(name, symbol) {
        _decimals = decimals_;
        _transferShouldFail = false;
    }

    function setTransferShouldFail(bool shouldFail) public {
        _transferShouldFail = shouldFail;
    }

    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        if (_transferShouldFail) {
            return false;
        }
        return super.transfer(to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public virtual override returns (bool) {
        if (_transferShouldFail) {
            return false;
        }
        return super.transferFrom(from, to, amount);
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }
} 