// SPDX-License-Identifier: MIT

pragma solidity ^0.8.25;

import {
  ValidatorRegistrationInput,
  ConversionData,
  Validator
} from "../interfaces/IValidatorManager.sol";
import {IPoAValidatorManager} from "../interfaces/IPoAValidatorManager.sol";

contract MockValidatorManager is IPoAValidatorManager {
    function initializeValidatorSet(
        ConversionData calldata conversionData,
        uint32 messageIndex
    ) external {
        // TODO: Implement
    }

    function initializeValidatorRegistration(
        ValidatorRegistrationInput calldata input,
        uint64 weight
    ) external returns (bytes32) {
        return randHash();
    }

    function completeValidatorRegistration(uint32 messageIndex) external {
        // TODO: Implement
    }

    function initializeEndValidation(bytes32 validationID) external returns (Validator memory) {
        // TODO: Implement
    }

    function completeEndValidation(uint32 messageIndex) external returns (bytes32 validationID, Validator memory validator){
        // TODO: Implement
    }

    function initializeValidatorWeightChange(bytes32 validationID, uint64 weight) external returns (uint64) {
        // TODO: Implement
    }

    function completeValidatorWeightChange(bytes32 validationID) external {
        // TODO: Implement
    }

    function resendEndValidatorMessage(bytes32 validationID) external {
      // TODO: Implement
    }

    function resendRegisterValidatorMessage(bytes32 validationID) external {
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