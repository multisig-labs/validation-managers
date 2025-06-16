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
  function test_submitUptimeProof_base() public {
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
    nftStakingManager.submitUptimeProof(uint32(0));

    vm.warp(epoch1AfterGracePeriod);
    uptimeMessage =
      ValidatorMessages.packValidationUptimeMessage(validationID, uint64(epoch1UptimeSeconds));
    vm.expectRevert(NFTStakingManager.GracePeriodHasPassed.selector);
    nftStakingManager.submitUptimeProof(uint32(0));

    vm.warp(epoch1InGracePeriod);
    uptimeMessage =
      ValidatorMessages.packValidationUptimeMessage(validationID, uint64(epoch1UptimeSeconds));
    nftStakingManager.submitUptimeProof(uint32(0));

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
    nftStakingManager.submitUptimeProof(uint32(0));

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

  function test_submitUptimeProof_insufficientUptime() public {
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
    nftStakingManager.submitUptimeProof(uint32(0));

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

  function test_submitUptimeProof_missUptime() public {
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

  function test_submitUptimeProof_cannotSubmitTwiceForSameEpoch() public {
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
    nftStakingManager.submitUptimeProof(uint32(0));

    vm.warp(block.timestamp + 10);

    bytes memory uptimeMessage2 =
      ValidatorMessages.packValidationUptimeMessage(validationID, uint64(uptimeForEpoch)); // Can be the same or different valid message

    _mockGetUptimeWarpMessage(uptimeMessage2, true, uint32(1)); // Using a new message index 1

    vm.expectRevert(NFTStakingManager.UptimeAlreadySubmitted.selector);
    nftStakingManager.submitUptimeProof(uint32(1));
  }

  function test_submitUptimeProof_cannotSubmitTwiceForSameEpoch_bypassUptimeCheck() public {
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
    nftStakingManager.submitUptimeProof(uint32(0));

    vm.warp(block.timestamp + 10);

    bytes memory uptimeMessage2 =
      ValidatorMessages.packValidationUptimeMessage(validationID, uint64(uptimeForEpoch)); // Can be the same or different valid message

    _mockGetUptimeWarpMessage(uptimeMessage2, true, uint32(1)); // Using a new message index 1

    vm.expectRevert(NFTStakingManager.UptimeAlreadySubmitted.selector);
    nftStakingManager.submitUptimeProof(uint32(1));
  }

  function test_submitUptimeProof_epochHasNotEnded() public {
    (bytes32 validationID,) = _createValidator();
    _createDelegation(validationID, 1);

    // Try to process proof before epoch has ended
    bytes memory uptimeMessage =
      ValidatorMessages.packValidationUptimeMessage(validationID, uint64(EPOCH_DURATION * 90 / 100));
    _mockGetUptimeWarpMessage(uptimeMessage, true, uint32(0));

    vm.expectRevert(NFTStakingManager.EpochHasNotEnded.selector);
    nftStakingManager.submitUptimeProof(uint32(0));
  }

  function test_submitUptimeProof_gracePeriodHasPassed() public {
    (bytes32 validationID,) = _createValidator();
    _createDelegation(validationID, 1);

    uint32 currentEpoch = nftStakingManager.getEpochByTimestamp(block.timestamp);

    // Warp past the grace period
    _warpAfterGracePeriod(currentEpoch);

    bytes memory uptimeMessage =
      ValidatorMessages.packValidationUptimeMessage(validationID, uint64(EPOCH_DURATION * 90 / 100));
    _mockGetUptimeWarpMessage(uptimeMessage, true, uint32(0));

    vm.expectRevert(NFTStakingManager.GracePeriodHasPassed.selector);
    nftStakingManager.submitUptimeProof(uint32(0));
  }

  function test_submitUptimeProof_invalidUptimeSeconds() public {
    (bytes32 validationID,) = _createValidator();
    _createDelegation(validationID, 1);

    uint32 currentEpoch = nftStakingManager.getEpochByTimestamp(block.timestamp);

    // First, submit a valid proof with high uptime
    _warpToGracePeriod(currentEpoch);
    uint64 initialUptime = uint64(EPOCH_DURATION * 90 / 100);
    bytes memory uptimeMessage1 =
      ValidatorMessages.packValidationUptimeMessage(validationID, initialUptime);
    _mockGetUptimeWarpMessage(uptimeMessage1, true, uint32(0));
    nftStakingManager.submitUptimeProof(uint32(0));

    // Move to next epoch
    vm.warp(nftStakingManager.getEpochEndTime(currentEpoch) + 1);
    uint32 nextEpoch = nftStakingManager.getEpochByTimestamp(block.timestamp);
    _warpToGracePeriod(nextEpoch);

    // Try to submit proof with lower uptime (should revert)
    uint64 lowerUptime = initialUptime - 1000; // Lower than previous
    bytes memory uptimeMessage2 =
      ValidatorMessages.packValidationUptimeMessage(validationID, lowerUptime);
    _mockGetUptimeWarpMessage(uptimeMessage2, true, uint32(1));

    vm.expectRevert(
      abi.encodeWithSelector(
        NFTStakingManager.InvalidUptimeSeconds.selector, lowerUptime, initialUptime
      )
    );
    nftStakingManager.submitUptimeProof(uint32(1));
  }

  function test_submitUptimeProof_validUptimeIncrease() public {
    (bytes32 validationID,) = _createValidator();
    _createDelegation(validationID, 1);

    uint32 currentEpoch = nftStakingManager.getEpochByTimestamp(block.timestamp);

    // First, submit a valid proof
    _warpToGracePeriod(currentEpoch);
    uint64 initialUptime = uint64(EPOCH_DURATION * 90 / 100);
    bytes memory uptimeMessage1 =
      ValidatorMessages.packValidationUptimeMessage(validationID, initialUptime);
    _mockGetUptimeWarpMessage(uptimeMessage1, true, uint32(0));
    nftStakingManager.submitUptimeProof(uint32(0));

    // Move to next epoch
    vm.warp(nftStakingManager.getEpochEndTime(currentEpoch) + 1);
    uint32 nextEpoch = nftStakingManager.getEpochByTimestamp(block.timestamp);
    _warpToGracePeriod(nextEpoch);

    // Submit proof with higher uptime (should succeed)
    uint64 higherUptime = initialUptime + uint64(EPOCH_DURATION * 90 / 100);
    bytes memory uptimeMessage2 =
      ValidatorMessages.packValidationUptimeMessage(validationID, higherUptime);
    _mockGetUptimeWarpMessage(uptimeMessage2, true, uint32(1));

    // Should not revert
    nftStakingManager.submitUptimeProof(uint32(1));

    // Verify the uptime was updated
    ValidationInfoView memory validation = nftStakingManager.getValidationInfoView(validationID);
    assertEq(validation.lastUptimeSeconds, higherUptime);
  }
}
