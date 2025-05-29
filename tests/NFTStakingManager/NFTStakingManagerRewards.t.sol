// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

import {
  DelegationInfoView,
  DelegatorStatus,
  EpochInfoView,
  NFTStakingManager,
  ValidationInfoView
} from "../../contracts/NFTStakingManager.sol";
import { NFTStakingManagerBase } from "../utils/NFTStakingManagerBase.sol";
import { console } from "forge-std/console.sol";

contract NFTStakingManagerRewardsTest is NFTStakingManagerBase {
  ///
  /// REWARDS TESTS
  ///
  function test_claimValidatorRewards_success() public {
    // Create validator and delegator
    (bytes32 validationID, address validator) = _createValidator();
    _createDelegation(validationID, 1);

    // Process proof and mint rewards for first epoch
    _warpToGracePeriod(1);
    _processUptimeProof(validationID, EPOCH_DURATION * 90 / 100);
    _warpAfterGracePeriod(1);
    _mintOneReward(validationID, 1);

    // Process proof and mint rewards for second epoch
    _warpToGracePeriod(2);
    _processUptimeProof(validationID, EPOCH_DURATION * 2 * 90 / 100);
    _warpAfterGracePeriod(2);
    _mintOneReward(validationID, 2);

    // Claim rewards as validator
    vm.startPrank(validator);
    (uint256 totalRewards, uint32[] memory claimedEpochNumbers) =
      nftStakingManager.claimValidatorRewards(validationID, 2);
    vm.stopPrank();

    // Verify rewards
    assertEq(totalRewards, epochRewards * 2 * DELEGATION_FEE_BIPS / BIPS_CONVERSION_FACTOR);
    assertEq(claimedEpochNumbers.length, 2);
    assertEq(claimedEpochNumbers[0], 1);
    assertEq(claimedEpochNumbers[1], 2);
  }

  function test_claimValidatorRewards_unauthorized() public {
    // Create validator and delegator
    (bytes32 validationID,) = _createValidator();
    _createDelegation(validationID, 1);

    // Process proof and mint rewards
    _warpToGracePeriod(1);
    _processUptimeProof(validationID, EPOCH_DURATION * 90 / 100);
    _warpAfterGracePeriod(1);
    _mintOneReward(validationID, 1);

    // Try to claim rewards as unauthorized address
    address unauthorized = getActor("Unauthorized");
    vm.startPrank(unauthorized);
    vm.expectRevert(NFTStakingManager.UnauthorizedOwner.selector);
    nftStakingManager.claimValidatorRewards(validationID, 1);
    vm.stopPrank();
  }

  function test_claimValidatorRewards_noRewards() public {
    // Create validator
    (bytes32 validationID, address validator) = _createValidator();

    // Try to claim rewards when none exist
    vm.startPrank(validator);
    (uint256 totalRewards, uint32[] memory claimedEpochNumbers) =
      nftStakingManager.claimValidatorRewards(validationID, 1);
    vm.stopPrank();

    assertEq(totalRewards, 0);
    assertEq(claimedEpochNumbers.length, 0);
  }

  function test_claimValidatorRewards_partialClaim() public {
    // Create validator and delegator
    (bytes32 validationID, address validator) = _createValidator();
    _createDelegation(validationID, 1);

    // Process proof and mint rewards for three epochs
    for (uint32 i = 1; i <= 3; i++) {
      _warpToGracePeriod(i);
      _processUptimeProof(validationID, EPOCH_DURATION * i * 90 / 100);
      _warpAfterGracePeriod(i);
      _mintOneReward(validationID, i);
    }

    // Claim only 2 epochs worth of rewards
    vm.startPrank(validator);
    (uint256 totalRewards, uint32[] memory claimedEpochNumbers) =
      nftStakingManager.claimValidatorRewards(validationID, 2);
    vm.stopPrank();

    // Verify first two epochs were claimed
    assertEq(totalRewards, epochRewards * 2 * DELEGATION_FEE_BIPS / BIPS_CONVERSION_FACTOR);
    assertEq(claimedEpochNumbers.length, 2);

    // Claim remaining epoch
    vm.startPrank(validator);
    (totalRewards, claimedEpochNumbers) = nftStakingManager.claimValidatorRewards(validationID, 1);
    vm.stopPrank();

    // Verify last epoch was claimed
    assertEq(totalRewards, epochRewards * DELEGATION_FEE_BIPS / BIPS_CONVERSION_FACTOR);
    assertEq(claimedEpochNumbers.length, 1);
  }

  function test_claimValidatorRewards_multipleDelegations_summedFees() public {
    // 1. Create validator
    (bytes32 validationID, address validator) = _createValidator();

    // 2. Create multiple delegators and delegations WITHOUT prepaid credits
    // Using unique names for actors in this test to avoid potential clashes.
    address delegator1 = getActor("Delegator1_MultiFeeTest");
    address delegator2 = getActor("Delegator2_MultiFeeTest");

    uint256 numLicenses1 = 2;
    uint256 numLicenses2 = 3;

    // These calls to _createDelegation will register and complete the delegations.
    // We are intentionally NOT calling setPrepaidCredits for delegator1 or delegator2.
    _createDelegation(validationID, delegator1, numLicenses1);
    _createDelegation(validationID, delegator2, numLicenses2);

    uint32 epochToTest = 1; // Test rewards for the first epoch after setup

    // 3. Process proof and mint rewards for the epoch
    _warpToGracePeriod(epochToTest);
    _processUptimeProof(validationID, EPOCH_DURATION * 90 / 100); // Sufficient uptime
    _warpAfterGracePeriod(epochToTest);
    _mintOneReward(validationID, epochToTest);

    // 4. Validator claims rewards
    vm.startPrank(validator);
    (uint256 totalClaimedRewards,) = nftStakingManager.claimValidatorRewards(validationID, 1); // Claim for 1 epoch
    vm.stopPrank();

    // 5. Calculate expected total fees
    // Total licenses staked in this epoch for this validator by these two delegators
    uint256 totalStakedLicensesInEpochByTheseDelegators = numLicenses1 + numLicenses2;

    EpochInfoView memory epochInfo = nftStakingManager.getEpochInfoView(epochToTest);

    assertEq(
      epochInfo.totalStakedLicenses,
      totalStakedLicensesInEpochByTheseDelegators,
      "Mismatch in expected total staked licenses for the epoch"
    );

    uint256 rewardsPerLicense = epochRewards / epochInfo.totalStakedLicenses;

    uint256 rewardsDelegation1 = numLicenses1 * rewardsPerLicense;
    uint256 feeDelegation1 = rewardsDelegation1 * DELEGATION_FEE_BIPS / BIPS_CONVERSION_FACTOR;

    uint256 rewardsDelegation2 = numLicenses2 * rewardsPerLicense;
    uint256 feeDelegation2 = rewardsDelegation2 * DELEGATION_FEE_BIPS / BIPS_CONVERSION_FACTOR;

    uint256 expectedTotalValidatorFees = feeDelegation1 + feeDelegation2;

    // 6. Assert claimed rewards match expected total fees
    assertEq(
      totalClaimedRewards,
      expectedTotalValidatorFees,
      "Validator rewards should be the sum of all delegation fees"
    );
  }

  function test_claimDelegatorRewards_success() public {
    // Create validator and delegator
    (bytes32 validationID,) = _createValidator();
    (bytes32 delegationID, address delegator) = _createDelegation(validationID, 1);

    // Process proof and mint rewards for first epoch
    _warpToGracePeriod(1);
    _processUptimeProof(validationID, EPOCH_DURATION * 90 / 100);
    _warpAfterGracePeriod(1);
    _mintOneReward(validationID, 1);

    // Process proof and mint rewards for second epoch
    _warpToGracePeriod(2);
    _processUptimeProof(validationID, EPOCH_DURATION * 2 * 90 / 100);
    _warpAfterGracePeriod(2);
    _mintOneReward(validationID, 2);

    // Claim rewards as delegator
    vm.startPrank(delegator);
    (uint256 totalRewards, uint32[] memory claimedEpochNumbers) =
      nftStakingManager.claimDelegatorRewards(delegationID, 2);
    vm.stopPrank();

    // Verify rewards (delegator gets full rewards minus delegation fee)
    uint256 expectedRewards =
      epochRewards * 2 * (BIPS_CONVERSION_FACTOR - DELEGATION_FEE_BIPS) / BIPS_CONVERSION_FACTOR;
    assertEq(totalRewards, expectedRewards);
    assertEq(claimedEpochNumbers.length, 2);
    assertEq(claimedEpochNumbers[0], 1);
    assertEq(claimedEpochNumbers[1], 2);
  }

  function test_claimDelegatorRewards_unauthorized() public {
    // Create validator and delegator
    (bytes32 validationID,) = _createValidator();
    (bytes32 delegationID,) = _createDelegation(validationID, 1);

    // Process proof and mint rewards
    _warpToGracePeriod(1);
    _processUptimeProof(validationID, EPOCH_DURATION * 90 / 100);
    _warpAfterGracePeriod(1);
    _mintOneReward(validationID, 1);

    // Try to claim rewards as unauthorized address
    address unauthorized = getActor("Unauthorized");
    vm.startPrank(unauthorized);
    vm.expectRevert(NFTStakingManager.UnauthorizedOwner.selector);
    nftStakingManager.claimDelegatorRewards(delegationID, 1);
    vm.stopPrank();
  }

  function test_claimDelegatorRewards_noRewards() public {
    // Create validator and delegator
    (bytes32 validationID,) = _createValidator();
    (bytes32 delegationID, address delegator) = _createDelegation(validationID, 1);

    // Try to claim rewards when none exist
    vm.startPrank(delegator);
    (uint256 totalRewards, uint32[] memory claimedEpochNumbers) =
      nftStakingManager.claimDelegatorRewards(delegationID, 1);
    vm.stopPrank();

    assertEq(totalRewards, 0);
    assertEq(claimedEpochNumbers.length, 0);
  }

  function test_claimDelegatorRewards_partialClaim() public {
    // Create validator and delegator
    (bytes32 validationID,) = _createValidator();
    (bytes32 delegationID, address delegator) = _createDelegation(validationID, 1);

    // Process proof and mint rewards for three epochs
    for (uint32 i = 1; i <= 3; i++) {
      _warpToGracePeriod(i);
      _processUptimeProof(validationID, EPOCH_DURATION * i * 90 / 100);
      _warpAfterGracePeriod(i);
      _mintOneReward(validationID, i);
    }

    // Claim only 2 epochs worth of rewards
    vm.startPrank(delegator);
    (uint256 totalRewards, uint32[] memory claimedEpochNumbers) =
      nftStakingManager.claimDelegatorRewards(delegationID, 2);
    vm.stopPrank();

    // Verify first two epochs were claimed
    uint256 expectedRewards =
      epochRewards * 2 * (BIPS_CONVERSION_FACTOR - DELEGATION_FEE_BIPS) / BIPS_CONVERSION_FACTOR;
    assertEq(totalRewards, expectedRewards);
    assertEq(claimedEpochNumbers.length, 2);

    // Claim remaining epoch
    vm.startPrank(delegator);
    (totalRewards, claimedEpochNumbers) = nftStakingManager.claimDelegatorRewards(delegationID, 1);
    vm.stopPrank();

    // Verify last epoch was claimed
    expectedRewards =
      epochRewards * (BIPS_CONVERSION_FACTOR - DELEGATION_FEE_BIPS) / BIPS_CONVERSION_FACTOR;
    assertEq(totalRewards, expectedRewards);
    assertEq(claimedEpochNumbers.length, 1);
  }

  function test_claimDelegatorRewards_withPrepaidCredits() public {
    // Create validator and delegator
    (bytes32 validationID, address validator) = _createValidator();
    (bytes32 delegationID, address delegator) = _createDelegation(validationID, 1);

    // Add prepaid credits
    vm.prank(validator);
    nftStakingManager.setPrepaidCredits(validator, delegator, uint32(2 * EPOCH_DURATION));

    // Process proof and mint rewards for two epochs
    for (uint32 i = 1; i <= 2; i++) {
      _warpToGracePeriod(i);
      _processUptimeProof(validationID, EPOCH_DURATION * i * 90 / 100);
      _warpAfterGracePeriod(i);
      _mintOneReward(validationID, i);
    }

    // Claim rewards as delegator
    vm.startPrank(delegator);
    (uint256 totalRewards, uint32[] memory claimedEpochNumbers) =
      nftStakingManager.claimDelegatorRewards(delegationID, 2);
    vm.stopPrank();

    // Verify delegator gets full rewards (no delegation fee due to prepaid credits)
    assertEq(totalRewards, epochRewards * 2);
    assertEq(claimedEpochNumbers.length, 2);
  }

  function test_getRewardsMintedForEpoch() public {
    (bytes32 validationID,) = _createValidator();
    _createDelegation(validationID, 1);

    uint32 epoch = nftStakingManager.getEpochByTimestamp(block.timestamp);
    _warpToGracePeriod(epoch);
    _processUptimeProof(validationID, EPOCH_DURATION);
    _warpAfterGracePeriod(epoch);

    _mintOneReward(validationID, epoch);

    uint256[] memory tokenIDs = nftStakingManager.getRewardsMintedForEpoch(epoch);
    assertEq(tokenIDs.length, 1);
  }

  function test_mintRewards_gracePeriodHasNotPassed() public {
    (bytes32 validationID,) = _createValidator();
    _createDelegation(validationID, 1);

    uint32 epoch = nftStakingManager.getEpochByTimestamp(block.timestamp);
    _warpToGracePeriod(epoch);
    _processUptimeProof(validationID, EPOCH_DURATION * 90 / 100);

    // Try to mint rewards before grace period has passed
    bytes32[] memory validationIDs = new bytes32[](1);
    validationIDs[0] = validationID;

    vm.expectRevert(NFTStakingManager.GracePeriodHasNotPassed.selector);
    nftStakingManager.mintRewards(validationIDs, epoch);
  }

  function test_mintRewards_multipleValidators() public {
    // Create two validators with delegations
    (bytes32 validationID1,) = _createValidator();
    (bytes32 validationID2,) = _createValidator();
    _createDelegation(validationID1, 1);
    _createDelegation(validationID2, 2);

    uint32 epoch = nftStakingManager.getEpochByTimestamp(block.timestamp);

    // Process proofs for both validators
    _warpToGracePeriod(epoch);
    _processUptimeProof(validationID1, EPOCH_DURATION * 90 / 100);
    _processUptimeProof(validationID2, EPOCH_DURATION * 90 / 100);

    // Mint rewards for both validators
    _warpAfterGracePeriod(epoch);
    bytes32[] memory validationIDs = new bytes32[](2);
    validationIDs[0] = validationID1;
    validationIDs[1] = validationID2;
    nftStakingManager.mintRewards(validationIDs, epoch);

    // Verify rewards were minted for all tokens
    uint256[] memory tokenIDs = nftStakingManager.getRewardsMintedForEpoch(epoch);
    assertEq(tokenIDs.length, 3); // 1 + 2 tokens
  }

  function test_claimDelegatorRewards_afterValidatorDeleted() public {
    // Create validator and delegator
    (bytes32 validationID, address validator) = _createValidator();
    (bytes32 delegationID, address delegator) = _createDelegation(validationID, 1);

    // Process proof and mint rewards for first epoch
    _warpToGracePeriod(1);
    _processUptimeProof(validationID, EPOCH_DURATION * 90 / 100);
    _warpAfterGracePeriod(1);
    _mintOneReward(validationID, 1);

    // Remove the delegation first (required before validator removal)
    bytes32[] memory delegationIDs = new bytes32[](1);
    delegationIDs[0] = delegationID;
    vm.prank(delegator);
    nftStakingManager.initiateDelegatorRemoval(delegationIDs);
    nftStakingManager.completeDelegatorRemoval(delegationID, 0);

    // Remove the validator
    vm.prank(validator);
    nftStakingManager.initiateValidatorRemoval(validationID);
    nftStakingManager.completeValidatorRemoval(0);

    // Validator claims their rewards first, which should delete the validation
    vm.prank(validator);
    nftStakingManager.claimValidatorRewards(validationID, 1);

    // Verify the validation has been deleted
    ValidationInfoView memory validationInfo = nftStakingManager.getValidationInfoView(validationID);
    assertEq(validationInfo.owner, address(0), "Validation should be deleted");

    // Now delegator should be able to claim rewards even after validator deletion
    vm.startPrank(delegator);
    (uint256 totalRewards, uint32[] memory claimedEpochNumbers) =
      nftStakingManager.claimDelegatorRewards(delegationID, 1);
    vm.stopPrank();

    // Verify the rewards are correct
    uint256 expectedRewards =
      epochRewards * (BIPS_CONVERSION_FACTOR - DELEGATION_FEE_BIPS) / BIPS_CONVERSION_FACTOR;
    assertEq(totalRewards, expectedRewards, "Delegator should receive correct rewards");
    assertEq(claimedEpochNumbers.length, 1, "Should claim 1 epoch");
    assertEq(claimedEpochNumbers[0], 1, "Should claim epoch 1");
  }

  function test_delegatorMissesRewardsAfterLeavingMidEpoch_BUG() public {
    // Create validator and delegator
    (bytes32 validationID, address validator) = _createValidator();
    (bytes32 delegationID, address delegator) = _createDelegation(validationID, 1);

    vm.prank(validator);
    nftStakingManager.setPrepaidCredits(validator, delegator, uint32(2 * EPOCH_DURATION));

    // Process proof and mint rewards for epoch 1
    _warpToGracePeriod(1);
    _processUptimeProof(validationID, EPOCH_DURATION * 90 / 100);
    _warpAfterGracePeriod(1);
    _mintOneReward(validationID, 1);

    // Move to the halfway point of epoch 2
    uint32 epoch2Start = nftStakingManager.getEpochEndTime(1);
    vm.warp(epoch2Start + (EPOCH_DURATION / 2) + 1); // Just past halfway point of epoch 2

    // Delegator leaves after halfway point
    bytes32[] memory delegationIDs = new bytes32[](1);
    delegationIDs[0] = delegationID;
    vm.prank(delegator);
    nftStakingManager.initiateDelegatorRemoval(delegationIDs);
    nftStakingManager.completeDelegatorRemoval(delegationID, 0);

    _warpToGracePeriod(2);

    // Claim rewards
    vm.prank(delegator);
    (uint256 totalRewards, uint32[] memory claimedEpochNumbers) =
      nftStakingManager.claimDelegatorRewards(delegationID, 1);
    console.log("somethingsomething");
    console.log(totalRewards);

    // Verify they got epoch 1 rewards
    assertEq(totalRewards, epochRewards, "Should receive epoch 1 rewards");

    _warpAfterGracePeriod(2);

    DelegationInfoView memory delegationInfo = nftStakingManager.getDelegationInfoView(delegationID);

    assertNotEq(
      delegationInfo.owner, address(0), "Delegation should still exist for epoch 2 rewards"
    );
  }
}
