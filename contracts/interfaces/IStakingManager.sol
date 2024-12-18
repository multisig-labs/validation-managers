// SPDX-License-Identifier: Ecosystem

pragma solidity 0.8.25;

import {ValidatorRegistrationInput, ValidatorStatus} from "./IValidatorManager.sol";

struct StakingInput {
  address owner;
  address tokenAddress; // address(0) for native
  uint256 amount;
  address nftAddress;
  uint256 nftId;
  uint64 minimumStakeDuration;
  ValidatorRegistrationInput input;
}

enum DelegatorStatus {
  Unknown,
  PendingAdded,
  Active,
  PendingRemoved
}


interface IStakingManager {
  event UptimeUpdated(bytes32 indexed validationID, uint64 uptime);

  error InvalidValidationID(bytes32 validationID);
  error InvalidValidatorStatus(ValidatorStatus status);
  error InvalidStakeAmount(uint256 stakeAmount);
  error InvalidMinStakeDuration(uint64 minStakeDuration);
  error InvalidValidatorManagerAddress(address validatorManagerAddress);
  error InvalidWarpOriginSenderAddress(address senderAddress);
  error InvalidValidatorManagerBlockchainID(bytes32 blockchainID);
  error InvalidWarpSourceChainID(bytes32 sourceChainID);
  error InvalidRegistrationExpiry(uint64 registrationExpiry);
  error InvalidInitializationStatus();
  error InvalidMaximumChurnPercentage(uint8 maximumChurnPercentage);
  error InvalidBLSKeyLength(uint256 length);
  error InvalidNodeID(bytes nodeID);
  error InvalidConversionID(bytes32 encodedConversionID, bytes32 expectedConversionID);
  error InvalidTotalWeight(uint64 weight);
  error InvalidWarpMessage();
  error MaxChurnRateExceeded(uint64 churnAmount);
  error NodeAlreadyRegistered(bytes nodeID);
  error UnexpectedRegistrationStatus(bool validRegistration);
  error InvalidPChainOwnerThreshold(uint256 threshold, uint256 addressesLength);
  error PChainOwnerAddressesNotSorted();
  error InvalidDelegationFee(uint16 delegationFeeBips);
  error InvalidDelegationID(bytes32 delegationID);
  error InvalidDelegatorStatus(DelegatorStatus status);
  error InvalidNonce(uint64 nonce);
  error InvalidRewardRecipient(address rewardRecipient);
  error InvalidStakeMultiplier(uint8 maximumStakeMultiplier);
  error MaxWeightExceeded(uint64 newValidatorWeight);
  error MinStakeDurationNotPassed(uint64 endTime);
  error UnauthorizedOwner(address sender);
  error ValidatorNotPoS(bytes32 validationID);
  error ValidatorIneligibleForRewards(bytes32 validationID);
  error DelegatorIneligibleForRewards(bytes32 delegationID);
  error ZeroWeightToValueFactor();
  error InvalidUptimeBlockchainID(bytes32 uptimeBlockchainID);

  function initializeStake(StakingInput calldata input) external payable returns (bytes32);
  function completeStake(uint32 messageIndex) external returns (bytes32);
}
