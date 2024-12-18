// (c) 2024, Ava Labs, Inc. All rights reserved.
// See the file LICENSE for licensing terms.

// SPDX-License-Identifier: Ecosystem

pragma solidity 0.8.25;

import {IValidatorManager, ValidatorRegistrationInput, Validator} from "./IValidatorManager.sol";

/**
 * @notice Interface for Proof of Authority Validator Manager contracts
 */
interface IPoAValidatorManager is IValidatorManager {

    /**
     * @notice Begins the process of ending an active validation period. The validation period must have been previously
     * started by a successful call to {completeValidatorRegistration} with the given validationID.
     * @param validationID The ID of the validation period being ended.
     */
    function initializeEndValidation(bytes32 validationID) external returns (Validator memory);
}
