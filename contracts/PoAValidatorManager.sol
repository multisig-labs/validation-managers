// (c) 2024, Ava Labs, Inc. All rights reserved.
// See the file LICENSE for licensing terms.

// SPDX-License-Identifier: Ecosystem

pragma solidity 0.8.25;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable@5.0.2/access/AccessControlUpgradeable.sol";
// Maybe look into AccessControlDefaultAdminRulesUpgradeable

import {ValidatorManager} from "./ValidatorManager.sol";
import {Validator, ValidatorManagerSettings, ValidatorRegistrationInput} from "./interfaces/IValidatorManager.sol";
import {IPoAValidatorManager} from "./interfaces/IPoAValidatorManager.sol";

contract PoAValidatorManager is IPoAValidatorManager, ValidatorManager, AccessControlUpgradeable {

  bytes32 public constant MANAGE_VALIDATOR_ROLE = keccak256("MANAGE_VALIDATOR_ROLE");

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize(ValidatorManagerSettings calldata settings, address admin) external initializer {
    __PoAValidatorManager_init(settings, admin);
  }

  function __PoAValidatorManager_init(ValidatorManagerSettings calldata settings, address admin) internal onlyInitializing {
    __ValidatorManager_init(settings);
    __AccessControl_init();
    _grantRole(DEFAULT_ADMIN_ROLE, admin);
    _grantRole(MANAGE_VALIDATOR_ROLE, admin);
  }

  function __PoAValidatorManager_init_unchained() internal onlyInitializing {}



  function initializeValidatorRegistration(ValidatorRegistrationInput calldata registrationInput, uint64 weight) external onlyRole(MANAGE_VALIDATOR_ROLE) returns (bytes32 validationID) {
    return _initializeValidatorRegistration(registrationInput, weight);
  }

  function initializeEndValidation(bytes32 validationID) external onlyRole(MANAGE_VALIDATOR_ROLE) returns (Validator memory){
    return _initializeEndValidation(validationID);
  }

  function completeEndValidation(uint32 messageIndex) external returns (bytes32 validationID, Validator memory validator){
    (validationID, validator) = _completeEndValidation(messageIndex);
  }

}
