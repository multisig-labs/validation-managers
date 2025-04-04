// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

import { PChainOwner } from "icm-contracts-8817f47/contracts/validator-manager/ACP99Manager.sol";

contract ValidatorManagerMock {
  mapping(bytes32 nodeIDHash => bool created) public created;
  mapping(bytes32 nodeIDHash => bool validating) public validating;

  bytes32 public lastNodeID;

  function initiateValidatorRegistration(
    bytes memory nodeID,
    bytes memory, //bls public key
    uint64, // registration expiry
    PChainOwner memory, // remaining balance owner
    PChainOwner memory, // disable owner
    uint64 // weight
  ) external returns (bytes32) {
    lastNodeID = keccak256(nodeID);
    created[lastNodeID] = true;
    return lastNodeID;
  }

  function completeValidatorRegistration(uint32) external returns (bytes32) {
    validating[lastNodeID] = true;
    created[lastNodeID] = false;
    return lastNodeID;
  }

  function initiateValidatorRemoval(bytes32 stakeID) external {
    validating[stakeID] = false;
  }

  function completeValidatorRemoval(uint32) external view returns (bytes32) {
    return lastNodeID;
  }
}
