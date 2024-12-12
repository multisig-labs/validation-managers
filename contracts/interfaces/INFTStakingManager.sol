// SPDX-License-Identifier: Ecosystem

pragma solidity 0.8.25;

import {IValidatorManager, ValidatorManagerSettings, ValidatorRegistrationInput} from "@avalabs/icm-contracts/validator-manager/interfaces/IValidatorManager.sol";
import {IRewardCalculator} from "@avalabs/icm-contracts/validator-manager/interfaces/IRewardCalculator.sol";
import {INFTLicenseModule} from "./INFTLicenseModule.sol";

struct NFTValidatorManagerSettings {
  ValidatorManagerSettings baseSettings;
  IRewardCalculator rewardCalculator;
  INFTLicenseModule licenseModule;
  address validatorReceiptAddress;
  bytes32 uptimeBlockchainID;
}

/// @notice validationId will map to this struct
struct NFTValidatorInfo {
  address nftAddress;
  uint256 nftId;
  uint256 receiptId;
  uint64 uptimeSeconds;
  uint256 redeemableValidatorRewards;
}


/**
 * Proof of Stake Validator Manager that stakes NFTs.
 */
interface INFTStakingManager is IValidatorManager {
  /**
   * @notice Begins the validator registration process. Locks the specified NFT in the contract as the stake.
   * @param registrationInput The inputs for a validator registration.
   */
  function initializeValidatorRegistration(
    ValidatorRegistrationInput calldata registrationInput, address nftAddress, uint256 nftId
  ) external returns (bytes32 validationID);
}
