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
import { ValidatorMessages } from
  "icm-contracts-2.0.0/contracts/validator-manager/ValidatorMessages.sol";

contract NFTStakingManagerProofProcessingTest is NFTStakingManagerBase {
  ///
  /// PROOF PROCESSING
  ///
  function test_processProof_base() public {
    uint256 startTime = block.timestamp;
    uint256 epochDuration = 1 days;

    uint256 epoch1InGracePeriod = startTime + epochDuration + GRACE_PERIOD / 2;
    uint256 epoch1AfterGracePeriod = startTime + epochDuration + GRACE_PERIOD + 1;

    uint256 epoch2InGracePeriod = startTime + epochDuration * 2 + GRACE_PERIOD - 1;
    uint256 epoch2AfterGracePeriod = startTime + epochDuration * 2 + GRACE_PERIOD + 1;

    uint256 epoch1UptimeSeconds = epochDuration * 90 / 100;
    uint256 epoch2UptimeSeconds = epoch1UptimeSeconds + epochDuration * 90 / 100;

    uint32 rewardsEpoch = nftStakingManager.getEpochByTimestamp(block.timestamp);
    (bytes32 validationID, address validator) = _createValidator();
    (bytes32 delegationID, address delegator) = _createDelegation(validationID, 1);

    vm.prank(validator);
    nftStakingManager.setPrepaidCredits(validator, delegator, uint32(epochDuration * 2));

    bytes memory uptimeMessage =
      ValidatorMessages.packValidationUptimeMessage(validationID, uint64(epoch1UptimeSeconds));
    _mockGetUptimeWarpMessage(uptimeMessage, true, uint32(0));
    vm.expectRevert(NFTStakingManager.EpochHasNotEnded.selector);
    nftStakingManager.processProof(uint32(0));

    vm.warp(epoch1AfterGracePeriod);
    uptimeMessage =
      ValidatorMessages.packValidationUptimeMessage(validationID, uint64(epoch1UptimeSeconds));
    vm.expectRevert(NFTStakingManager.GracePeriodHasPassed.selector);
    nftStakingManager.processProof(uint32(0));

    vm.warp(epoch1InGracePeriod);
    uptimeMessage =
      ValidatorMessages.packValidationUptimeMessage(validationID, uint64(epoch1UptimeSeconds));
    nftStakingManager.processProof(uint32(0));

    EpochInfoView memory epoch = nftStakingManager.getEpochInfoView(rewardsEpoch);
    assertEq(epoch.totalStakedLicenses, 1);

    vm.warp(epoch1AfterGracePeriod);
    _mintOneReward(validationID, rewardsEpoch);

    // check that the delegator has rewards
    uint256 rewards = nftStakingManager.getRewardsForEpoch(delegationID, rewardsEpoch);
    assertEq(rewards, epochRewards);
    rewardsEpoch = nftStakingManager.getEpochByTimestamp(block.timestamp);

    vm.warp(epoch2InGracePeriod);
    uptimeMessage =
      ValidatorMessages.packValidationUptimeMessage(validationID, uint64(epoch2UptimeSeconds));
    _mockGetUptimeWarpMessage(uptimeMessage, true, uint32(0));
    nftStakingManager.processProof(uint32(0));

    vm.warp(epoch2AfterGracePeriod);
    _mintOneReward(validationID, rewardsEpoch);

    rewards = nftStakingManager.getRewardsForEpoch(delegationID, rewardsEpoch);
    assertEq(rewards, epochRewards);

    vm.prank(delegator);
    (uint256 totalRewards, uint32[] memory claimedEpochNumbers) =
      nftStakingManager.claimDelegatorRewards(delegationID, 2);

    assertEq(totalRewards, epochRewards * 2);
    assertEq(claimedEpochNumbers.length, 2);
    assertEq(claimedEpochNumbers[0], rewardsEpoch - 1);
    assertEq(claimedEpochNumbers[1], rewardsEpoch);
  }

  function test_processProof_insufficientUptime() public {
    uint256 startTime = block.timestamp;
    uint256 epochDuration = 1 days;

    (bytes32 validationID,) = _createValidator();
    (bytes32 delegationID,) = _createDelegation(validationID, 1);

    uint32 epoch = nftStakingManager.getEpochByTimestamp(startTime);
    uint256 insufficientUptime = epochDuration * 70 / 100;

    // Process proof with insufficient uptime
    _warpToGracePeriod(epoch);
    bytes memory uptimeMessage =
      ValidatorMessages.packValidationUptimeMessage(validationID, uint64(insufficientUptime));
    _mockGetUptimeWarpMessage(uptimeMessage, true, uint32(0));
    nftStakingManager.processProof(uint32(0));

    // Verify that the uptime and submissiontime were set properly
    ValidationInfoView memory validation = nftStakingManager.getValidationInfoView(validationID);
    assertEq(validation.lastUptimeSeconds, insufficientUptime);
    assertEq(validation.lastSubmissionTime, block.timestamp);

    // Verify that the delegation did not receive rewards
    _warpAfterGracePeriod(epoch);
    _mintOneReward(validationID, 1);
    uint256 rewards = nftStakingManager.getRewardsForEpoch(delegationID, 1);
    assertEq(rewards, 0);
  }

  function test_processProof_missUptime() public {
    uint256 startTime =
      nftStakingManager.getEpochEndTime(nftStakingManager.getEpochByTimestamp(block.timestamp) - 1);
    uint256 epochDuration = 1 days;

    (bytes32 validationID, address validator) = _createValidator();
    (bytes32 delegationID, address delegator) = _createDelegation(validationID, 1);

    vm.prank(validator);
    nftStakingManager.setPrepaidCredits(validator, delegator, uint32(epochDuration * 2));

    uint256 epoch1InGracePeriod = startTime + epochDuration + GRACE_PERIOD / 2;
    uint256 epoch1AfterGracePeriod = startTime + epochDuration + GRACE_PERIOD + 1;
    uint256 epoch3AfterGracePeriod = startTime + epochDuration * 3 + GRACE_PERIOD + 1;

    vm.warp(epoch1InGracePeriod);
    _processUptimeProof(validationID, (uint256(epochDuration) * 90) / 100);

    vm.warp(epoch1AfterGracePeriod);
    _mintOneReward(validationID, 1);

    // skip second epoch
    vm.warp(startTime + epochDuration * 2);

    // process proof for third epoch
    vm.warp(startTime + epochDuration * 3 + GRACE_PERIOD / 2);
    _processUptimeProof(validationID, (uint256(epochDuration) * 3 * 90) / 100);

    EpochInfoView memory epoch =
      nftStakingManager.getEpochInfoView(nftStakingManager.getEpochByTimestamp(block.timestamp) - 1);
    assertEq(epoch.totalStakedLicenses, 1);

    vm.warp(epoch3AfterGracePeriod);
    _mintOneReward(validationID, 3);
    uint256 rewards = nftStakingManager.getRewardsForEpoch(delegationID, 3);
    assertEq(rewards, epochRewards);
  }

  function test_processProof_cannotSubmitTwiceForSameEpoch() public {
    (bytes32 validationID, address validator) = _createValidator();
    _createDelegation(validationID, 1); // Create a delegation so there's something to process

    uint32 epochToTest = nftStakingManager.getEpochByTimestamp(block.timestamp);

    vm.prank(validator);
    nftStakingManager.setPrepaidCredits(
      validator, getActor("Delegator1"), uint32(EPOCH_DURATION * 2)
    );

    _warpToGracePeriod(epochToTest);

    uint256 uptimeForEpoch = uint256(EPOCH_DURATION) * 90 / 100; // 90% uptime
    bytes memory uptimeMessage1 =
      ValidatorMessages.packValidationUptimeMessage(validationID, uint64(uptimeForEpoch));

    _mockGetUptimeWarpMessage(uptimeMessage1, true, uint32(0)); // Using message index 0
    nftStakingManager.processProof(uint32(0));

    vm.warp(block.timestamp + 10);

    bytes memory uptimeMessage2 =
      ValidatorMessages.packValidationUptimeMessage(validationID, uint64(uptimeForEpoch)); // Can be the same or different valid message

    _mockGetUptimeWarpMessage(uptimeMessage2, true, uint32(1)); // Using a new message index 1

    vm.expectRevert(NFTStakingManager.UptimeAlreadySubmitted.selector);
    nftStakingManager.processProof(uint32(1));
  }

  function test_processProof_cannotSubmitTwiceForSameEpoch_bypassUptimeCheck() public {
    vm.prank(admin);
    nftStakingManager.setBypassUptimeCheck(true);

    (bytes32 validationID, address validator) = _createValidator();
    _createDelegation(validationID, 1);

    uint32 epochToTest = nftStakingManager.getEpochByTimestamp(block.timestamp);

    vm.prank(validator);
    nftStakingManager.setPrepaidCredits(
      validator, getActor("Delegator1"), uint32(EPOCH_DURATION * 2)
    );

    _warpToGracePeriod(epochToTest);

    uint256 uptimeForEpoch = uint256(EPOCH_DURATION) * 90 / 100; // 90% uptime
    bytes memory uptimeMessage1 =
      ValidatorMessages.packValidationUptimeMessage(validationID, uint64(uptimeForEpoch));

    _mockGetUptimeWarpMessage(uptimeMessage1, true, uint32(0)); // Using message index 0
    nftStakingManager.processProof(uint32(0));

    vm.warp(block.timestamp + 10);

    bytes memory uptimeMessage2 =
      ValidatorMessages.packValidationUptimeMessage(validationID, uint64(uptimeForEpoch)); // Can be the same or different valid message

    _mockGetUptimeWarpMessage(uptimeMessage2, true, uint32(1)); // Using a new message index 1

    vm.expectRevert(NFTStakingManager.UptimeAlreadySubmitted.selector);
    nftStakingManager.processProof(uint32(1));
  }

  function test_processProof_updatesLicenseCount() public {
    // Create validator
    (bytes32 validationID,) = _createValidator();

    // Create delegation with multiple licenses
    uint256 numLicenses = 3;
    (bytes32 delegationID, address delegator) = _createDelegation(validationID, numLicenses);

    // Check initial license count (should be set when delegation is created)
    ValidationInfoView memory validationInfo = nftStakingManager.getValidationInfoView(validationID);
    assertEq(
      validationInfo.licenseCount, numLicenses, "Initial license count should match delegation size"
    );

    // Remove the delegation
    bytes32[] memory delegationIDs = new bytes32[](1);
    delegationIDs[0] = delegationID;
    vm.prank(delegator);
    nftStakingManager.initiateDelegatorRemoval(delegationIDs);
    nftStakingManager.completeDelegatorRemoval(delegationID, 0);

    // Verify delegation is no longer active
    DelegationInfoView memory delegationInfo = nftStakingManager.getDelegationInfoView(delegationID);
    assertEq(
      uint8(delegationInfo.status), uint8(DelegatorStatus.Removed), "Delegation should be removed"
    );

    // License count should still be the same before processProof
    validationInfo = nftStakingManager.getValidationInfoView(validationID);
    assertEq(
      validationInfo.licenseCount, numLicenses, "License count should not change until processProof"
    );

    // Process proof to trigger license count update
    uint32 currentEpoch = nftStakingManager.getEpochByTimestamp(block.timestamp);
    _warpToGracePeriod(currentEpoch);
    _processUptimeProof(validationID, EPOCH_DURATION * 90 / 100);

    // Check that license count was updated (reduced)
    validationInfo = nftStakingManager.getValidationInfoView(validationID);
    assertEq(
      validationInfo.licenseCount,
      0,
      "License count should be 0 after processProof with removed delegation"
    );
  }

  function test_processProof_updatesLicenseCount_insufficientUptime() public {
    // Create validator
    (bytes32 validationID,) = _createValidator();

    // Create delegation with multiple licenses
    uint256 numLicenses = 3;
    (bytes32 delegationID, address delegator) = _createDelegation(validationID, numLicenses);

    // Check initial license count (should be set when delegation is created)
    ValidationInfoView memory validationInfo = nftStakingManager.getValidationInfoView(validationID);
    assertEq(
      validationInfo.licenseCount, numLicenses, "Initial license count should match delegation size"
    );

    // Remove the delegation
    bytes32[] memory delegationIDs = new bytes32[](1);
    delegationIDs[0] = delegationID;
    vm.prank(delegator);
    nftStakingManager.initiateDelegatorRemoval(delegationIDs);
    nftStakingManager.completeDelegatorRemoval(delegationID, 0);

    // Verify delegation is no longer active
    DelegationInfoView memory delegationInfo = nftStakingManager.getDelegationInfoView(delegationID);
    assertEq(
      uint8(delegationInfo.status), uint8(DelegatorStatus.Removed), "Delegation should be removed"
    );

    // License count should still be the same before processProof
    validationInfo = nftStakingManager.getValidationInfoView(validationID);
    assertEq(
      validationInfo.licenseCount, numLicenses, "License count should not change until processProof"
    );

    // Process proof to trigger license count update
    uint32 currentEpoch = nftStakingManager.getEpochByTimestamp(block.timestamp);
    _warpToGracePeriod(currentEpoch);
    _processUptimeProof(validationID, 0);

    // Check that license count was updated (reduced)
    validationInfo = nftStakingManager.getValidationInfoView(validationID);
    assertEq(
      validationInfo.licenseCount,
      0,
      "License count should be 0 after processProof with removed delegation"
    );
  }

  function test_processProof_epochHasNotEnded() public {
    (bytes32 validationID,) = _createValidator();
    _createDelegation(validationID, 1);

    uint32 currentEpoch = nftStakingManager.getEpochByTimestamp(block.timestamp);

    // Try to process proof before epoch has ended
    bytes memory uptimeMessage =
      ValidatorMessages.packValidationUptimeMessage(validationID, uint64(EPOCH_DURATION * 90 / 100));
    _mockGetUptimeWarpMessage(uptimeMessage, true, uint32(0));

    vm.expectRevert(NFTStakingManager.EpochHasNotEnded.selector);
    nftStakingManager.processProof(uint32(0));
  }

  function test_processProof_gracePeriodHasPassed() public {
    (bytes32 validationID,) = _createValidator();
    _createDelegation(validationID, 1);

    uint32 currentEpoch = nftStakingManager.getEpochByTimestamp(block.timestamp);

    // Warp past the grace period
    _warpAfterGracePeriod(currentEpoch);

    bytes memory uptimeMessage =
      ValidatorMessages.packValidationUptimeMessage(validationID, uint64(EPOCH_DURATION * 90 / 100));
    _mockGetUptimeWarpMessage(uptimeMessage, true, uint32(0));

    vm.expectRevert(NFTStakingManager.GracePeriodHasPassed.selector);
    nftStakingManager.processProof(uint32(0));
  }
}
