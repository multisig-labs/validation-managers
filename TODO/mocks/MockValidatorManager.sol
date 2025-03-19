// SPDX-License-Identifier: MIT

pragma solidity ^0.8.25;

import {
  ACP99ValidatorManager, ConversionData, Validator, ValidatorRegistrationInput
} from "icm-contracts/contracts/validator-manager/ACP99Manager.sol";

contract MockValidatorManager is ACP99ValidatorManager {
  function initializeValidatorSet(ConversionData calldata conversionData, uint32 messageIndex) external {
    // TODO: Implement
  }

  function initializeValidatorRegistration(ValidatorRegistrationInput calldata input, uint64 weight) external returns (bytes32) {
    return randHash();
  }

  function completeValidatorRegistration(uint32 messageIndex) external returns (bytes32) {
    // TODO: Implement
  }

  function initializeEndValidation(bytes32 validationID) external {
    // TODO: Implement
  }

  function completeEndValidation(uint32 messageIndex) external returns (bytes32) {
    // TODO: Implement
  }

  function initializeValidatorWeightChange(bytes32 validationID, uint64 weight) external returns (uint64) {
    // TODO: Implement
  }

  function completeValidatorWeightChange(bytes32 validationID) external {
    // TODO: Implement
  }

  // These shouldn't be in this interface, but put them here for now
  function getChurnPeriodSeconds() external view returns (uint64) {
    // TODO: Implement
  }
  function getValidator(bytes32 validationID) external view returns (Validator memory) {
    // TODO: Implement
  }

  uint256 private randNonce = 0;

  function randHash() internal returns (bytes32) {
    randNonce++;
    return keccak256(abi.encodePacked(randNonce, blockhash(block.timestamp)));
  }
}
