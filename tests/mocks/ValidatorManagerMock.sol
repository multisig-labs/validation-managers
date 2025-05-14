// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

import { console2 } from "forge-std/console2.sol";
import {
  PChainOwner,
  Validator,
  ValidatorStatus
} from "icm-contracts-2.0.0/contracts/validator-manager/interfaces/IACP99Manager.sol";

contract MockValidatorManager {
  mapping(bytes32 validationID => Validator validator) public validators;

  uint64 public constant REGISTRATION_EXPIRY_LENGTH = 1 days;

  bytes32 public lastValidationID;
  bytes32 public badValidationID;

  uint256 private randNonce = 0;

  function initiateValidatorRegistration(
    bytes memory, // nodeID
    bytes memory, //bls public key
    PChainOwner memory, // remaining balance owner
    PChainOwner memory, // disable owner
    uint64 weight // weight
  ) external returns (bytes32) {
    bytes32 validationID = _getValidationID();

    lastValidationID = validationID;

    validators[validationID] = Validator({
      status: ValidatorStatus.PendingAdded,
      nodeID: bytes.concat(validationID),
      startingWeight: weight,
      weight: weight,
      startTime: 0,
      endTime: 0,
      sentNonce: 0,
      receivedNonce: 0
    });

    return validationID;
  }

  function getValidator(bytes32 validationId) external view returns (Validator memory) {
    return validators[validationId];
  }

  function completeValidatorRegistration(uint32) external returns (bytes32) {
    // get the last validationID,
    // how do I parse the message from the messageIndex?
    Validator storage validator = validators[lastValidationID];

    validator.status = ValidatorStatus.Active;
    validator.startTime = uint64(block.timestamp);

    return lastValidationID;
  }

  function initiateValidatorRemoval(bytes32 validationID) external {
    Validator storage validator = validators[validationID];
    validator.status = ValidatorStatus.PendingRemoved;
    validator.endTime = uint64(block.timestamp);

    lastValidationID = validationID;
  }

  function completeValidatorRemoval(uint32) external returns (bytes32) {
    Validator storage validator = validators[lastValidationID];
    validator.status = ValidatorStatus.Completed;

    return lastValidationID;
  }

  function _getValidationID() internal returns (bytes32) {
    randNonce++;
    return keccak256(abi.encodePacked(block.timestamp, randNonce, address(this)));
  }

  function initiateValidatorWeightUpdate(bytes32 validationId, uint64 weight)
    external
    returns (uint64, bytes32)
  {
    Validator storage validator = validators[validationId];
    uint64 nonce = getNextNonce();

    validator.sentNonce = nonce;
    validator.weight = weight;

    lastValidationID = validationId;

    return (nonce, randomBytes32());
  }

  function completeValidatorWeightUpdate(uint32) external returns (bytes32, uint64) {
    Validator storage validator = validators[lastValidationID];
    validator.receivedNonce = validator.sentNonce;

    if (badValidationID != bytes32(0)) {
      bytes32 id = badValidationID;
      badValidationID = bytes32(0);
      return (id, validator.receivedNonce);
    }

    return (lastValidationID, validator.receivedNonce);
  }

  function setInvalidNonce(bytes32 validationID, uint64 badNonce) external {
    Validator storage validator = validators[validationID];
    validator.sentNonce = badNonce;
  }

  function setBadValidationID(bytes32 bad) external {
    badValidationID = bad;
  }

  function subnetID() external pure returns (bytes32) {
    return bytes32(keccak256(abi.encodePacked("mockvalidatormanager")));
  }

  function getNextNonce() internal returns (uint64) {
    randNonce++;
    return uint64(randNonce);
  }

  function randomBytes32() public returns (bytes32) {
    randNonce++;
    return keccak256(abi.encodePacked(block.timestamp, randNonce, address(this)));
  }

  function setNonce(bytes32 validationID, uint64 nonce) external {
    Validator storage validator = validators[validationID];
    validator.receivedNonce = nonce;
  }
}
