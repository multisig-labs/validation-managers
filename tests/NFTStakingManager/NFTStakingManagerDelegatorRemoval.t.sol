// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

import {
  DelegationInfoView,
  DelegatorStatus,
  NFTStakingManager
} from "../../contracts/NFTStakingManager.sol";
import { NFTStakingManagerBase } from "../utils/NFTStakingManagerBase.sol";
import { console2 } from "forge-std-1.9.6/src/console2.sol";

contract NFTStakingManagerDelegatorRemovalTest is NFTStakingManagerBase {
  //
  // DELEGATOR REMOVAL
  //
  function test_initiateDelegatorRemoval_unauthorized() public {
    // Create validator and delegator
    (bytes32 validationID,) = _createValidator();
    (bytes32 delegationID,) = _createDelegation(validationID, 1);

    // Unauthorized caller cannot initiate removal
    address unauthorized = getActor("Unauthorized");
    vm.startPrank(unauthorized);
    vm.expectRevert(NFTStakingManager.UnauthorizedOwner.selector);
    bytes32[] memory delegationIDs = new bytes32[](1);
    delegationIDs[0] = delegationID;
    nftStakingManager.initiateDelegatorRemoval(delegationIDs);
    vm.stopPrank();
  }

  function test_initiateDelegatorRemoval_invalidStatus() public {
    // Create validator and delegator
    (bytes32 validationID,) = _createValidator();
    (bytes32 delegationID, address delegator) = _createDelegation(validationID, 1);

    bytes32[] memory delegationIDs = new bytes32[](1);
    delegationIDs[0] = delegationID;

    // First initiate removal to change status to PendingRemoved
    vm.startPrank(delegator);
    nftStakingManager.initiateDelegatorRemoval(delegationIDs);
    vm.stopPrank();

    // Try to remove again - should fail
    vm.startPrank(delegator);
    vm.expectRevert(
      abi.encodeWithSelector(
        NFTStakingManager.InvalidDelegatorStatus.selector, DelegatorStatus.PendingRemoved
      )
    );
    nftStakingManager.initiateDelegatorRemoval(delegationIDs);
    vm.stopPrank();
  }

  function test_initiateDelegatorRemoval_byValidator() public {
    // Create validator and delegator
    (bytes32 validationID, address validator) = _createValidator();
    (bytes32 delegationID,) = _createDelegation(validationID, 1);

    bytes32[] memory delegationIDs = new bytes32[](1);
    delegationIDs[0] = delegationID;

    // Validator initiates removal
    vm.startPrank(validator);
    nftStakingManager.initiateDelegatorRemoval(delegationIDs);
    vm.stopPrank();

    // Verify state changes
    DelegationInfoView memory delegation = nftStakingManager.getDelegationInfoView(delegationID);
    assertEq(uint8(delegation.status), uint8(DelegatorStatus.PendingRemoved));
    assertEq(delegation.endEpoch, nftStakingManager.getEpochByTimestamp(block.timestamp) - 1);
  }

  function test_initiateDelegatorRemoval_multiple() public {
    // Create validator and delegator
    (bytes32 validationID, address validator) = _createValidator();
    bytes32[] memory delegationIDs = _createMultipleDelegations(validationID, validator, 3);

    // Remove all delegations at once
    vm.startPrank(validator);
    nftStakingManager.initiateDelegatorRemoval(delegationIDs);
    vm.stopPrank();

    // Verify all delegations are in PendingRemoved state
    for (uint256 i = 0; i < delegationIDs.length; i++) {
      DelegationInfoView memory delegation =
        nftStakingManager.getDelegationInfoView(delegationIDs[i]);
      assertEq(uint8(delegation.status), uint8(DelegatorStatus.PendingRemoved));
      assertEq(delegation.endEpoch, nftStakingManager.getEpochByTimestamp(block.timestamp) - 1);
    }
  }

  function test_delegationEndEpoch_firstHalf() public {
    (bytes32 validationID, address validator) = _createValidator();
    (bytes32 delegationID, address delegator) = _createDelegation(validationID, 1);

    vm.prank(validator);
    nftStakingManager.setPrepaidCredits(validator, delegator, uint32(EPOCH_DURATION));

    skip(EPOCH_DURATION);
    uint32 currentEpoch = nftStakingManager.getEpochByTimestamp(block.timestamp);

    uint32 epochStartTime = nftStakingManager.getEpochEndTime(currentEpoch - 1);
    uint32 firstQuarterTime = epochStartTime + (EPOCH_DURATION / 4);

    vm.warp(firstQuarterTime);
    console2.log("firstQuarterTime", firstQuarterTime);

    bytes32[] memory delegationIDs = new bytes32[](1);
    delegationIDs[0] = delegationID;
    vm.prank(delegator);
    nftStakingManager.initiateDelegatorRemoval(delegationIDs);

    DelegationInfoView memory delegation1 = nftStakingManager.getDelegationInfoView(delegationID);
    assertEq(
      delegation1.endEpoch,
      currentEpoch - 1,
      "End epoch should be previous epoch when removed in first half"
    );
  }

  function test_delegationEndEpoch_secondHalf() public {
    (bytes32 validationID, address validator) = _createValidator();
    (bytes32 delegationID, address delegator) = _createDelegation(validationID, 1);

    vm.prank(validator);
    nftStakingManager.setPrepaidCredits(validator, delegator, uint32(EPOCH_DURATION));

    skip(EPOCH_DURATION);

    skip(EPOCH_DURATION);
    uint32 currentEpoch = nftStakingManager.getEpochByTimestamp(block.timestamp);

    uint32 epochStartTime = nftStakingManager.getEpochEndTime(currentEpoch - 1);
    uint32 thirdQuarterTime = epochStartTime + (EPOCH_DURATION * 3 / 4);
    vm.warp(thirdQuarterTime);

    bytes32[] memory delegationIDs = new bytes32[](1);
    delegationIDs[0] = delegationID;
    vm.prank(delegator);
    nftStakingManager.initiateDelegatorRemoval(delegationIDs);

    DelegationInfoView memory delegation2 = nftStakingManager.getDelegationInfoView(delegationID);
    assertEq(
      delegation2.endEpoch,
      currentEpoch,
      "End epoch should be current epoch when removed in second half"
    );
  }

  //
  // COMPLETE DELEGATOR REMOVAL
  //
  function test_completeDelegatorRemoval_invalidStatus() public {
    // Create validator and delegator
    (bytes32 validationID,) = _createValidator();
    (bytes32 delegationID,) = _createDelegation(validationID, 1);

    // Try to complete removal without initiating it first
    vm.expectRevert(
      abi.encodeWithSelector(
        NFTStakingManager.InvalidDelegatorStatus.selector, DelegatorStatus.Active
      )
    );
    nftStakingManager.completeDelegatorRemoval(delegationID, 0);
  }

  function test_completeDelegatorRemoval_invalidNonce() public {
    // Create validator and delegator
    (bytes32 validationID,) = _createValidator();
    (bytes32 delegationID, address delegator) = _createDelegation(validationID, 1);

    // Initiate removal
    bytes32[] memory delegationIDs = new bytes32[](1);
    delegationIDs[0] = delegationID;
    vm.prank(delegator);
    nftStakingManager.initiateDelegatorRemoval(delegationIDs);

    DelegationInfoView memory delegation = nftStakingManager.getDelegationInfoView(delegationID);

    validatorManager.setInvalidNonce(validationID, delegation.endingNonce - 1);

    // Mock a weight update with a lower nonce than the delegation's ending nonce
    vm.expectRevert(
      abi.encodeWithSelector(NFTStakingManager.InvalidNonce.selector, delegation.endingNonce - 1)
    );
    nftStakingManager.completeDelegatorRemoval(delegationID, 0);
  }

  function test_completeDelegatorRemoval_unexpectedValidationID() public {
    // Create two validators
    (bytes32 validationID1,) = _createValidator();
    _createValidator();

    // Create delegations for both validators
    (bytes32 delegationID1, address delegator) = _createDelegation(validationID1, 1);

    // Initiate removal for first delegation
    bytes32[] memory delegationIDs = new bytes32[](1);
    delegationIDs[0] = delegationID1;
    vm.prank(delegator);
    nftStakingManager.initiateDelegatorRemoval(delegationIDs);

    bytes32 bogusValidationID = validatorManager.randomBytes32();
    validatorManager.setBadValidationID(bogusValidationID);

    // Mock a weight update for the wrong validator
    vm.expectRevert(
      abi.encodeWithSelector(
        NFTStakingManager.UnexpectedValidationID.selector, bogusValidationID, validationID1
      )
    );
    nftStakingManager.completeDelegatorRemoval(delegationID1, 0);
  }

  function test_completeDelegatorRemoval_success() public {
    // Create validator and delegator
    (bytes32 validationID,) = _createValidator();
    (bytes32 delegationID, address delegator) = _createDelegation(validationID, 1);

    // Initiate removal
    bytes32[] memory delegationIDs = new bytes32[](1);
    delegationIDs[0] = delegationID;
    vm.prank(delegator);
    nftStakingManager.initiateDelegatorRemoval(delegationIDs);

    // Complete removal
    bytes32 returnedDelegationID = nftStakingManager.completeDelegatorRemoval(delegationID, 0);
    assertEq(returnedDelegationID, delegationID);

    // Verify tokens are unlocked
    DelegationInfoView memory delegation = nftStakingManager.getDelegationInfoView(delegationID);
    for (uint256 i = 0; i < delegation.tokenIDs.length; i++) {
      assertEq(nftStakingManager.getTokenLockedBy(delegation.tokenIDs[i]), bytes32(0));
    }
  }

  function test_completeDelegatorRemoval_multipleDelegations() public {
    // Create validator and delegator
    (bytes32 validationID, address validator) = _createValidator();
    bytes32[] memory delegationIDs = _createMultipleDelegations(validationID, validator, 3);

    // Initiate removal for all delegations
    vm.prank(validator);
    nftStakingManager.initiateDelegatorRemoval(delegationIDs);

    // Complete removal for each delegation
    for (uint256 i = 0; i < delegationIDs.length; i++) {
      nftStakingManager.completeDelegatorRemoval(delegationIDs[i], 0);

      // Verify tokens are unlocked
      DelegationInfoView memory delegation =
        nftStakingManager.getDelegationInfoView(delegationIDs[i]);
      for (uint256 j = 0; j < delegation.tokenIDs.length; j++) {
        assertEq(nftStakingManager.getTokenLockedBy(delegation.tokenIDs[j]), bytes32(0));
      }
    }
  }
}
