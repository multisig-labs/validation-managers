// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

import {
  DelegationInfoView,
  DelegatorStatus,
  NFTStakingManager,
  ValidationInfoView
} from "../../contracts/NFTStakingManager.sol";
import { NFTStakingManagerBase } from "../utils/NFTStakingManagerBase.sol";
import { Validator } from
  "icm-contracts-2.0.0/contracts/validator-manager/interfaces/IACP99Manager.sol";

contract NFTStakingManagerNonceTest is NFTStakingManagerBase {
  ///
  /// NONCE TESTS
  ///
  function test_overlappingDelegationWeightUpdates() public {
    // Create validator
    (bytes32 validationID, address validator) = _createValidator();

    // Create two delegators
    address delegator1 = getActor("Delegator1");
    address delegator2 = getActor("Delegator2");

    // Mint tokens for both delegators
    uint256[] memory tokenIDs1 = new uint256[](1);
    uint256[] memory tokenIDs2 = new uint256[](1);
    tokenIDs1[0] = nft.mint(delegator1);
    tokenIDs2[0] = nft.mint(delegator2);

    // Add prepaid credits
    vm.startPrank(validator);
    nftStakingManager.setPrepaidCredits(validator, delegator1, uint32(1 days));
    nftStakingManager.setPrepaidCredits(validator, delegator2, uint32(1 days));
    vm.stopPrank();

    // First delegator initiates registration, should get a lower nonce number
    vm.prank(delegator1);
    bytes32 delegationID1 = nftStakingManager.initiateDelegatorRegistration(validationID, tokenIDs1);

    DelegationInfoView memory delegation1 = nftStakingManager.getDelegationInfoView(delegationID1);
    uint64 firstNonce = delegation1.startingNonce;

    Validator memory v = validatorManager.getValidator(validationID);
    assertEq(v.weight, NODE_LICENSE_WEIGHT);
    assertEq(v.sentNonce, firstNonce);
    assertEq(v.receivedNonce, 0);

    // Second delegator initiates registration, should get another nonce number that's higher
    vm.prank(delegator2);
    bytes32 delegationID2 = nftStakingManager.initiateDelegatorRegistration(validationID, tokenIDs2);

    DelegationInfoView memory delegation2 = nftStakingManager.getDelegationInfoView(delegationID2);
    uint64 secondNonce = delegation2.startingNonce;

    v = validatorManager.getValidator(validationID);
    assertEq(v.weight, NODE_LICENSE_WEIGHT * 2);
    assertEq(v.sentNonce, secondNonce);
    assertEq(v.receivedNonce, 0);

    // Complete weight update for second delegation
    nftStakingManager.completeDelegatorRegistration(delegationID2, uint32(0));

    v = validatorManager.getValidator(validationID);
    assertEq(v.weight, NODE_LICENSE_WEIGHT * 2);
    assertEq(v.receivedNonce, secondNonce);

    nftStakingManager.completeDelegatorRegistration(delegationID1, uint32(0));

    v = validatorManager.getValidator(validationID);

    assertEq(v.weight, NODE_LICENSE_WEIGHT * 2);
    assertEq(v.receivedNonce, secondNonce);

    // Verify both delegations are active
    delegation1 = nftStakingManager.getDelegationInfoView(delegationID1);
    delegation2 = nftStakingManager.getDelegationInfoView(delegationID2);
    assertEq(uint8(delegation1.status), uint8(DelegatorStatus.Active));
    assertEq(uint8(delegation2.status), uint8(DelegatorStatus.Active));
  }

  function test_DelegationsByOwner_EndsAndRewardsClaimedIsRemoved() public {
    (bytes32 validationID, address validatorOwner) = _createValidator();

    address delegator1 = getActor("DelegatorForScenarioA");

    vm.prank(validatorOwner);
    nftStakingManager.setPrepaidCredits(validatorOwner, delegator1, uint32(1 * EPOCH_DURATION));
    bytes32 delegationID1 = _createDelegation(validationID, delegator1, 1);

    assertEq(
      nftStakingManager.getDelegationsByOwner(delegator1).length,
      1,
      "Initial delegation count should be 1"
    );
    assertEq(
      nftStakingManager.getDelegationsByOwner(delegator1)[0],
      delegationID1,
      "Initial delegation ID mismatch"
    );

    uint32 rewardsEpoch = nftStakingManager.getEpochByTimestamp(block.timestamp);

    _warpToGracePeriod(rewardsEpoch);
    _processUptimeProof(validationID, EPOCH_DURATION);

    _warpAfterGracePeriod(rewardsEpoch);
    _mintOneReward(validationID, rewardsEpoch);

    bytes32[] memory delegationIdArray = new bytes32[](1);
    delegationIdArray[0] = delegationID1;

    vm.startPrank(delegator1);
    nftStakingManager.initiateDelegatorRemoval(delegationIdArray);
    vm.stopPrank();
    nftStakingManager.completeDelegatorRemoval(delegationID1, 0);

    vm.warp(block.timestamp + EPOCH_DURATION * 2);

    vm.prank(delegator1);
    (uint256 d1TotalRewards,) = nftStakingManager.claimDelegatorRewards(delegationID1, 1);
    assertGt(d1TotalRewards, 0, "Should have claimed some rewards");

    assertEq(
      nftStakingManager.getDelegationsByOwner(delegator1).length, 0, "Delegation should be removed"
    );
    DelegationInfoView memory delegationInfo =
      nftStakingManager.getDelegationInfoView(delegationID1);
    assertEq(
      uint8(delegationInfo.status), uint8(DelegatorStatus.Unknown), "Delegation should be removed"
    );
    assertEq(
      delegationInfo.owner,
      address(0),
      "Delegation owner should not exist after removal without rewards"
    );
  }

  function test_DelegationsByOwner_EndsNotClaimedStays_ThenClaimedIsRemoved() public {
    (bytes32 validationID, address validatorOwner) = _createValidator();

    address delegator2 = getActor("DelegatorForScenarioB");
    uint32 rewardsEpoch;
    bytes32[] memory delegationIdArray = new bytes32[](1);

    vm.prank(validatorOwner);
    nftStakingManager.setPrepaidCredits(validatorOwner, delegator2, uint32(1 * EPOCH_DURATION));
    bytes32 delegationID2 = _createDelegation(validationID, delegator2, 1);
    assertEq(
      nftStakingManager.getDelegationsByOwner(delegator2).length,
      1,
      "Initial delegation count should be 1"
    );

    rewardsEpoch = nftStakingManager.getEpochByTimestamp(block.timestamp);
    _warpToGracePeriod(rewardsEpoch);
    _processUptimeProof(validationID, EPOCH_DURATION);
    _warpAfterGracePeriod(rewardsEpoch);
    _mintOneReward(validationID, rewardsEpoch);

    vm.startPrank(delegator2);
    delegationIdArray[0] = delegationID2;
    nftStakingManager.initiateDelegatorRemoval(delegationIdArray);
    vm.stopPrank();
    nftStakingManager.completeDelegatorRemoval(delegationID2, 0);

    vm.warp(block.timestamp + EPOCH_DURATION * 2);

    assertEq(
      nftStakingManager.getDelegationsByOwner(delegator2).length,
      1,
      "Delegation should STILL be present as rewards not claimed"
    );
    DelegationInfoView memory delegationInfo =
      nftStakingManager.getDelegationInfoView(delegationID2);
    assertEq(
      uint8(delegationInfo.status),
      uint8(DelegatorStatus.Removed),
      "Delegation should be in PendingRemoved status"
    );

    vm.prank(delegator2);
    (uint256 d2TotalRewards,) = nftStakingManager.claimDelegatorRewards(delegationID2, 1);
    assertGt(d2TotalRewards, 0, "Should have claimed some rewards");

    assertEq(
      nftStakingManager.getDelegationsByOwner(delegator2).length,
      0,
      "Delegation should be removed after claiming rewards"
    );
    delegationInfo = nftStakingManager.getDelegationInfoView(delegationID2);
    assertEq(
      uint8(delegationInfo.status),
      uint8(DelegatorStatus.Unknown),
      "Delegation should be removed after claiming rewards"
    );
  }

  function test_DelegationsByOwner_ActiveAndRewardsClaimedStays() public {
    (bytes32 validationID, address validatorOwner) = _createValidator();

    address delegator3 = getActor("DelegatorForScenarioC");
    uint32 rewardsEpoch;

    vm.prank(validatorOwner);
    nftStakingManager.setPrepaidCredits(validatorOwner, delegator3, uint32(1 * EPOCH_DURATION));
    bytes32 delegationID3 = _createDelegation(validationID, delegator3, 1);
    assertEq(
      nftStakingManager.getDelegationsByOwner(delegator3).length,
      1,
      "Initial delegation count should be 1"
    );

    rewardsEpoch = nftStakingManager.getEpochByTimestamp(block.timestamp);
    _warpToGracePeriod(rewardsEpoch);
    _processUptimeProof(validationID, EPOCH_DURATION);
    _warpAfterGracePeriod(rewardsEpoch);
    _mintOneReward(validationID, rewardsEpoch);

    vm.prank(delegator3);
    (uint256 d3TotalRewards,) = nftStakingManager.claimDelegatorRewards(delegationID3, 1);
    assertGt(d3TotalRewards, 0, "Should have claimed some rewards");

    // Delegation is NOT ended
    assertEq(
      nftStakingManager.getDelegationsByOwner(delegator3).length,
      1,
      "Delegation should STILL be present as it's active"
    );
    DelegationInfoView memory delegationInfo =
      nftStakingManager.getDelegationInfoView(delegationID3);
    assertEq(
      uint8(delegationInfo.status), uint8(DelegatorStatus.Active), "Delegation should be active"
    );
  }

  function test_ValidatorRemoval_WithRewards_DoesNotRemoveFromOwnerMapping() public {
    (bytes32 validationID, address validatorOwner) = _createValidator();
    (bytes32 delegationID, address delegatorOwner) = _createDelegation(validationID, 1);

    assertEq(
      nftStakingManager.getValidationsByOwner(validatorOwner).length,
      1,
      "Validator should initially be in validationsByOwner"
    );

    // Process rewards for an epoch
    uint32 epoch = nftStakingManager.getEpochByTimestamp(block.timestamp);
    _warpToGracePeriod(epoch);
    _processUptimeProof(validationID, EPOCH_DURATION);
    _warpAfterGracePeriod(epoch);
    _mintOneReward(validationID, epoch);

    // Remove the delegation first - validator (owner) or delegator can do this.
    // Here, let's have the delegator remove their own stake.
    bytes32[] memory delegationIDsToRemove = new bytes32[](1);
    delegationIDsToRemove[0] = delegationID;
    vm.prank(delegatorOwner);
    nftStakingManager.initiateDelegatorRemoval(delegationIDsToRemove);
    nftStakingManager.completeDelegatorRemoval(delegationID, 0);

    // Initiate and complete validator removal
    vm.prank(validatorOwner);
    nftStakingManager.initiateValidatorRemoval(validationID);
    nftStakingManager.completeValidatorRemoval(0);

    assertEq(
      nftStakingManager.getValidationsByOwner(validatorOwner).length,
      1,
      "Validator should STILL be in validationsByOwner due to pending rewards"
    );

    ValidationInfoView memory validationInfo = nftStakingManager.getValidationInfoView(validationID);
    assertEq(
      validationInfo.owner,
      validatorOwner,
      "Validation owner should be the same as the validator owner"
    );

    // Claim validator rewards
    vm.prank(validatorOwner);
    (uint256 totalRewards,) = nftStakingManager.claimValidatorRewards(validationID, 1);
    assertGt(totalRewards, 0, "Validator should have claimed rewards");

    assertEq(
      nftStakingManager.getValidationsByOwner(validatorOwner).length,
      0,
      "Validator should be removed from validationsByOwner after rewards are claimed"
    );

    validationInfo = nftStakingManager.getValidationInfoView(validationID);
    assertEq(
      validationInfo.owner,
      address(0),
      "Validation owner should not exist after rewards are claimed"
    );
  }

  function test_DelegatorRemoval_WithRewards_DoesNotRemoveFromOwnerMapping() public {
    (bytes32 validationID, /* address validatorOwner */ ) = _createValidator();
    (bytes32 delegationID, address delegatorOwner) = _createDelegation(validationID, 1);

    assertEq(
      nftStakingManager.getDelegationsByOwner(delegatorOwner).length,
      1,
      "Delegation should initially be in delegationsByOwner"
    );

    // Process rewards for an epoch
    uint32 epoch = nftStakingManager.getEpochByTimestamp(block.timestamp);
    _warpToGracePeriod(epoch);
    _processUptimeProof(validationID, EPOCH_DURATION);
    _warpAfterGracePeriod(epoch);
    _mintOneReward(validationID, epoch);

    // Initiate and complete delegator removal
    bytes32[] memory delegationIDsToRemove = new bytes32[](1);
    delegationIDsToRemove[0] = delegationID;
    vm.prank(delegatorOwner);
    nftStakingManager.initiateDelegatorRemoval(delegationIDsToRemove);
    nftStakingManager.completeDelegatorRemoval(delegationID, 0);

    assertEq(
      nftStakingManager.getDelegationsByOwner(delegatorOwner).length,
      1,
      "Delegation should STILL be in delegationsByOwner due to pending rewards"
    );
    DelegationInfoView memory delegationInfo = nftStakingManager.getDelegationInfoView(delegationID);
    assertEq(
      uint8(delegationInfo.status),
      uint8(DelegatorStatus.Removed),
      "Delegation should be in PendingRemoved status"
    );
    assertEq(
      delegationInfo.owner,
      delegatorOwner,
      "Delegation owner should be the same as the delegator owner"
    );

    // Claim delegator rewards
    vm.prank(delegatorOwner);
    (uint256 totalRewards,) = nftStakingManager.claimDelegatorRewards(delegationID, 1);
    assertGt(totalRewards, 0, "Delegator should have claimed rewards");

    assertEq(
      nftStakingManager.getDelegationsByOwner(delegatorOwner).length,
      0,
      "Delegation should be removed from delegationsByOwner after rewards are claimed"
    );
    delegationInfo = nftStakingManager.getDelegationInfoView(delegationID);
    assertEq(
      uint8(delegationInfo.status),
      uint8(DelegatorStatus.Unknown),
      "Delegation should be removed after rewards are claimed"
    );
    assertEq(
      delegationInfo.owner,
      address(0),
      "Delegation owner should not exist after rewards are claimed"
    );
  }

  function test_nonce_sequentialIncrement() public {
    (bytes32 validationID, ) = _createValidator();

    address delegator1 = getActor("Delegator1");
    address delegator2 = getActor("Delegator2");

    uint256[] memory tokenIDs1 = new uint256[](1);
    uint256[] memory tokenIDs2 = new uint256[](1);
    tokenIDs1[0] = nft.mint(delegator1);
    tokenIDs2[0] = nft.mint(delegator2);

    // First delegation
    vm.prank(delegator1);
    bytes32 delegationID1 = nftStakingManager.initiateDelegatorRegistration(validationID, tokenIDs1);

    DelegationInfoView memory delegation1 = nftStakingManager.getDelegationInfoView(delegationID1);
    uint64 firstNonce = delegation1.startingNonce;

    // Second delegation should have higher nonce
    vm.prank(delegator2);
    bytes32 delegationID2 = nftStakingManager.initiateDelegatorRegistration(validationID, tokenIDs2);

    DelegationInfoView memory delegation2 = nftStakingManager.getDelegationInfoView(delegationID2);
    uint64 secondNonce = delegation2.startingNonce;

    assertGt(secondNonce, firstNonce, "Second nonce should be greater than first");
  }

  function test_nonce_removalNonceTracking() public {
    (bytes32 validationID, ) = _createValidator();
    (bytes32 delegationID, address delegator) = _createDelegation(validationID, 1);

    // Initiate removal
    bytes32[] memory delegationIDs = new bytes32[](1);
    delegationIDs[0] = delegationID;
    vm.prank(delegator);
    nftStakingManager.initiateDelegatorRemoval(delegationIDs);

    DelegationInfoView memory delegation = nftStakingManager.getDelegationInfoView(delegationID);
    assertGt(
      delegation.endingNonce,
      delegation.startingNonce,
      "Ending nonce should be greater than starting nonce"
    );
  }
}
