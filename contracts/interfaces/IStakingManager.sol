// SPDX-License-Identifier: Ecosystem

pragma solidity 0.8.25;

import {ValidatorRegistrationInput} from "./IValidatorManager.sol";

struct StakingInput {
  address staker;
  address tokenAddress; // address(0) for native
  uint256 amount;
  address nftAddress;
  uint256 nftId;
  uint64 minimumStakeDuration;
  ValidatorRegistrationInput input;
}

interface IStakingManager {
  function initializeStake(StakingInput calldata input) external payable returns (bytes32);
  function completeStake(uint32 messageIndex) external returns (bytes32);
}
