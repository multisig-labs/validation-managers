// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

import { PChainOwner } from "icm-contracts-8817f47/contracts/validator-manager/ACP99Manager.sol";

contract MockValidatorManager {
  mapping(bytes32 nodeIDHash => bool created) public created;
  mapping(bytes32 nodeIDHash => bool validating) public validating;
  mapping(bytes32 nodeIDHash => bool pendingRemoval) public pendingRemoval;
  mapping(bytes32 nodeIDHash => uint64 weight) public weights;
  bytes32 public lastNodeID;

  uint256 private randNonce = 0;

  function initiateValidatorRegistration(
    bytes memory, // nodeID
    bytes memory, //bls public key
    uint64, // registration expiry
    PChainOwner memory, // remaining balance owner
    PChainOwner memory, // disable owner
    uint64 weight // weight
  ) external returns (bytes32) {
    lastNodeID = _getValidationID();
    created[lastNodeID] = true;
    weights[lastNodeID] = weight;
    return lastNodeID;
  }

  function completeValidatorRegistration(uint32) external returns (bytes32) {
    validating[lastNodeID] = true;
    created[lastNodeID] = false;
    return lastNodeID;
  }

  function initiateValidatorRemoval(bytes32 stakeID) external {
    lastNodeID = stakeID;
    pendingRemoval[stakeID] = true;
    validating[stakeID] = false;
  }

  function completeValidatorRemoval(uint32) external returns (bytes32) {
    pendingRemoval[lastNodeID] = false;
    return lastNodeID;
  }

  function _getValidationID() internal returns (bytes32) {
    randNonce++;
    return keccak256(abi.encodePacked(block.timestamp, randNonce, address(this)));
  }
}
