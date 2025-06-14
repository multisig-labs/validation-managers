// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.25;

import { AggregatorV3Interface } from
  "chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";

contract MockChainlinkPriceFeed is AggregatorV3Interface, AccessControl {
  uint256 public price;
  uint8 public dec = 8;

  constructor(uint256 startingPrice) {
    price = startingPrice;
  }

  function setDecimals(uint8 newDecimals) public {
    dec = newDecimals;
  }

  function setPrice(uint256 newPrice) public {
    price = newPrice;
  }

  function decimals() external view returns (uint8) {
    return dec;
  }

  function description() external pure returns (string memory) {
    return string("MockPriceFeed");
  }

  function version() external pure returns (uint256) {
    return 1;
  }

  function getRoundData(uint80)
    external
    view
    returns (
      uint80 roundId,
      int256 answer,
      uint256 startedAt,
      uint256 updatedAt,
      uint80 answeredInRound
    )
  {
    return (uint80(1), int256(price), uint256(block.timestamp), uint256(block.timestamp), uint80(1));
  }

  function latestRoundData()
    external
    view
    returns (
      uint80 roundId,
      int256 answer,
      uint256 startedAt,
      uint256 updatedAt,
      uint80 answeredInRound
    )
  {
    return (uint80(1), int256(price), uint256(block.timestamp), uint256(block.timestamp), uint80(1));
  }
}
