// SPDX-License-Identifier: Ecosystem

pragma solidity 0.8.25;

import {ValidatorRegistrationInput} from "@avalabs/icm-contracts/validator-manager/interfaces/IValidatorManager.sol";
import {IRewardCalculator} from "@avalabs/icm-contracts/validator-manager/interfaces/IRewardCalculator.sol";

// struct ValidatorRegistrationInput {
//     bytes nodeID;
//     bytes blsPublicKey;
//     uint64 registrationExpiry;
//     PChainOwner remainingBalanceOwner;
//     PChainOwner disableOwner;
// }

struct StakingInputNFT {
  address staker;
  address nftAddress;
  uint256 nftId;
  uint64 minimumStakeDuration;
  ValidatorRegistrationInput input;
}

struct StakingInputToken {
  address staker;
  address tokenAddress; // address(0) for native
  uint256 amount;
  uint64 minimumStakeDuration;
  ValidatorRegistrationInput input;
}


interface IStakingManager {
  function initializeStakeNFT(StakingInputNFT calldata input) external returns (bytes32);
  function completeStakeNFT(uint32 messageIndex) external returns (bytes32);

  function initializeStakeToken(StakingInputToken calldata input) payable external returns (bytes32);
  function completeStakeToken(uint32 messageIndex) external returns (bytes32);
}
