// (c) 2024, Ava Labs, Inc. All rights reserved.
// See the file LICENSE for licensing terms.

// SPDX-License-Identifier: Ecosystem

pragma solidity 0.8.25;

import {ValidatorStatus, Validator, ValidatorRegistrationInput, ConversionData} from "@avalabs/icm-contracts/validator-manager/interfaces/IValidatorManager.sol";

interface IACP99ValidatorManager {
    function initializeValidatorSet(
        ConversionData calldata conversionData,
        uint32 messageIndex
    ) external;

    function initializeValidatorRegistration(
        ValidatorRegistrationInput calldata input,
        uint64 weight
    ) external returns (bytes32);

    function completeValidatorRegistration(uint32 messageIndex) external  returns (bytes32) ;

    function initializeEndValidation(bytes32 validationID) external;

    function completeEndValidation(uint32 messageIndex) external returns (bytes32);

    function initializeValidatorWeightChange(bytes32 validationID, uint64 weight) external returns (uint64) ;

    function completeValidatorWeightChange(bytes32 validationID) external;

    // These shouldn't be in this interface, but put them here for now
    function getChurnPeriodSeconds() external view returns (uint64);
    function getValidator(bytes32 validationID) external view returns (Validator memory);
}