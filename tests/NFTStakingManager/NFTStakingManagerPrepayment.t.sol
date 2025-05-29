// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

import { NFTStakingManager } from "../../contracts/NFTStakingManager.sol";
import { NFTStakingManagerBase } from "../utils/NFTStakingManagerBase.sol";
import { ValidatorMessages } from
  "icm-contracts-2.0.0/contracts/validator-manager/ValidatorMessages.sol";

contract NFTStakingManagerPrepaymentTest is NFTStakingManagerBase {
  //
  // DELEGATION FEE
  //
  function test_DelegationFee_NoCredits() public {
    (bytes32 validationID,) = _createValidator();
    (bytes32 delegationID,) = _createDelegation(validationID, 1);

    vm.warp(block.timestamp + 1 days + 1 seconds);
    bytes memory uptimeMessage =
      ValidatorMessages.packValidationUptimeMessage(validationID, uint64(1 days));
    _mockGetUptimeWarpMessage(uptimeMessage, true, uint32(0));
    nftStakingManager.processProof(uint32(0));

    vm.warp(block.timestamp + 1 hours);
    _mintOneReward(validationID, 1);
    uint256 rewards = nftStakingManager.getRewardsForEpoch(delegationID, 1);
    assertEq(rewards, 900 ether);
  }

  function test_DelegationFee_AllCredits_OneLicense() public {
    (bytes32 validationID, address validator) = _createValidator();
    (bytes32 delegationID, address delegator) = _createDelegation(validationID, 1);

    vm.prank(validator);
    nftStakingManager.setPrepaidCredits(validator, delegator, 1 days);

    vm.warp(block.timestamp + 1 days + 1 seconds);
    bytes memory uptimeMessage =
      ValidatorMessages.packValidationUptimeMessage(validationID, uint64(1 days));
    _mockGetUptimeWarpMessage(uptimeMessage, true, uint32(0));

    nftStakingManager.processProof(uint32(0));

    vm.warp(block.timestamp + 1 hours);
    _mintOneReward(validationID, 1);
    uint256 rewards = nftStakingManager.getRewardsForEpoch(delegationID, 1);
    assertEq(rewards, 1000 ether);
  }

  function test_DelegationFee_AllCredits_10Licenses() public {
    (bytes32 validationID, address validator) = _createValidator();
    (bytes32 delegationID, address delegator) = _createDelegation(validationID, 10);

    vm.prank(validator);
    nftStakingManager.setPrepaidCredits(validator, delegator, 10 days);

    vm.warp(block.timestamp + 1 days + 1 seconds);
    bytes memory uptimeMessage =
      ValidatorMessages.packValidationUptimeMessage(validationID, uint64(1 days));
    _mockGetUptimeWarpMessage(uptimeMessage, true, uint32(0));
    nftStakingManager.processProof(uint32(0));

    vm.warp(block.timestamp + 1 hours);
    _mintOneReward(validationID, 1);
    uint256 rewards = nftStakingManager.getRewardsForEpoch(delegationID, 1);
    assertEq(rewards, 1000 ether);
  }

  function test_DelegationFee_HalfCredits_10Licenses() public {
    (bytes32 validationID, address validator) = _createValidator();
    (bytes32 delegationID, address delegator) = _createDelegation(validationID, 10);

    vm.prank(validator);
    nftStakingManager.setPrepaidCredits(validator, delegator, 5 days);

    vm.warp(block.timestamp + 1 days + 1 seconds);
    bytes memory uptimeMessage =
      ValidatorMessages.packValidationUptimeMessage(validationID, uint64(1 days));
    _mockGetUptimeWarpMessage(uptimeMessage, true, uint32(0));
    nftStakingManager.processProof(uint32(0));

    vm.warp(block.timestamp + 1 hours);
    _mintOneReward(validationID, 1);
    uint256 rewards = nftStakingManager.getRewardsForEpoch(delegationID, 1);
    assertEq(rewards, 500 ether + 500 ether * 90 / 100);
  }

  function test_multipleDelegatorsWithDifferentTokens() public {
    uint256 startTime = block.timestamp;
    uint256 epochInGracePeriod = startTime + 1 days + GRACE_PERIOD / 2;
    uint256 epochAfterGracePeriod = startTime + 1 days + GRACE_PERIOD + 1;

    // Create validator
    (bytes32 validationID, address validator) = _createValidator();

    // Create delegators with different token amounts
    address delegator1 = getActor("Delegator1");
    address delegator2 = getActor("Delegator2");
    address delegator3 = getActor("Delegator3");

    // Record prepayments for all tokens
    vm.startPrank(validator);
    nftStakingManager.setPrepaidCredits(validator, delegator1, uint32(1 days));
    nftStakingManager.setPrepaidCredits(validator, delegator2, uint32(2 days));
    nftStakingManager.setPrepaidCredits(validator, delegator3, uint32(3 days));
    vm.stopPrank();

    // Create delegations with different token amounts
    bytes32 delegationId1 = _createDelegation(validationID, delegator1, 1);
    bytes32 delegationId2 = _createDelegation(validationID, delegator2, 2);
    bytes32 delegationId3 = _createDelegation(validationID, delegator3, 3);

    // Process proof for the epoch
    vm.warp(epochInGracePeriod);
    bytes memory uptimeMessage =
      ValidatorMessages.packValidationUptimeMessage(validationID, uint64(1 days * 90 / 100));
    _mockGetUptimeWarpMessage(uptimeMessage, true, uint32(0));
    nftStakingManager.processProof(uint32(0));

    // Mint rewards after grace period
    vm.warp(epochAfterGracePeriod);
    uint32 currentEpoch = nftStakingManager.getEpochByTimestamp(block.timestamp) - 1;
    _mintOneReward(validationID, currentEpoch);

    // Calculate expected rewards per token
    uint256 rewardsPerToken = epochRewards / 6; // Total rewards divided by total tokens

    // Verify each delegator's rewards
    uint256 rewards1 = nftStakingManager.getRewardsForEpoch(delegationId1, currentEpoch);
    assertEq(rewards1, rewardsPerToken * 1); // 1 token worth of rewards

    uint256 rewards2 = nftStakingManager.getRewardsForEpoch(delegationId2, currentEpoch);
    assertEq(rewards2, rewardsPerToken * 2); // 2 tokens worth of rewards

    uint256 rewards3 = nftStakingManager.getRewardsForEpoch(delegationId3, currentEpoch);
    assertEq(rewards3, rewardsPerToken * 3); // 3 tokens worth of rewards
  }

  //
  // PREPAYMENT TESTS
  //
  function test_prepayment_oneEntity_multipleValidators() public {
    // Create a hardware provider who will manage multiple validators
    address hardwareProvider = getActor("HardwareProvider");
    vm.startPrank(admin);
    nftStakingManager.grantRole(nftStakingManager.PREPAYMENT_ROLE(), hardwareProvider);
    vm.stopPrank();

    // Create two validators for the same hardware provider
    uint256 hardwareTokenId1 = hardwareNft.mint(hardwareProvider);
    uint256 hardwareTokenId2 = hardwareNft.mint(hardwareProvider);

    (bytes32 validationID1,) = _createValidator(hardwareProvider, hardwareTokenId1);
    (bytes32 validationID2,) = _createValidator(hardwareProvider, hardwareTokenId2);

    address delegator = getActor("Delegator");
    // Create a delegator with multiple licenses
    uint256[] memory tokenIDs = new uint256[](2);
    tokenIDs[0] = nft.mint(delegator);
    tokenIDs[1] = nft.mint(delegator);

    {
      // Hardware provider adds prepaid credits for the delegator
      vm.prank(hardwareProvider);
      nftStakingManager.setPrepaidCredits(hardwareProvider, delegator, uint32(5 * EPOCH_DURATION)); // Prepay for 5 days

      // Delegator registers with first validator
      bytes32 delegationID1 = _createDelegation(validationID1, delegator, tokenIDs);

      uint32 epoch = nftStakingManager.getEpochByTimestamp(block.timestamp);
      uint64 uptime = uint64(EPOCH_DURATION * 90 / 100);
      // Process first epoch
      _warpToGracePeriod(epoch);
      bytes memory uptimeMessage =
        ValidatorMessages.packValidationUptimeMessage(validationID1, uptime);
      _mockGetUptimeWarpMessage(uptimeMessage, true, uint32(0));
      nftStakingManager.processProof(uint32(0));

      // Mint rewards after grace period
      _warpAfterGracePeriod(epoch);
      _mintOneReward(validationID1, epoch);

      // Verify delegator got full rewards (no delegation fee due to prepayment)
      uint256 rewards = nftStakingManager.getRewardsForEpoch(delegationID1, epoch);
      assertEq(rewards, epochRewards);

      // Remove delegator from first validator
      vm.prank(delegator);
      bytes32[] memory delegationIDs = new bytes32[](1);
      delegationIDs[0] = delegationID1;
      nftStakingManager.initiateDelegatorRemoval(delegationIDs);
      nftStakingManager.completeDelegatorRemoval(delegationID1, 0);

      // claim rewards
      vm.prank(delegator);
      (uint256 claimedRewards,) = nftStakingManager.claimDelegatorRewards(delegationID1, 1);
      assertEq(claimedRewards, epochRewards);
    }

    {
      // Delegator registers with second validator
      bytes32 delegationID2 = _createDelegation(validationID2, delegator, tokenIDs);

      uint32 epoch = nftStakingManager.getEpochByTimestamp(block.timestamp);
      uint64 uptime = uint64(EPOCH_DURATION * 2 * 90 / 100);
      // Process second epoch
      _warpToGracePeriod(epoch);
      bytes memory uptimeMessage =
        ValidatorMessages.packValidationUptimeMessage(validationID2, uptime);
      _mockGetUptimeWarpMessage(uptimeMessage, true, uint32(0));
      nftStakingManager.processProof(uint32(0));

      // Mint rewards after grace period
      _warpAfterGracePeriod(epoch);
      _mintOneReward(validationID2, epoch);

      // Verify delegator still gets full rewards with second validator (prepayment still valid)
      uint256 rewards = nftStakingManager.getRewardsForEpoch(delegationID2, epoch);
      assertEq(rewards, epochRewards);

      // Claim rewards
      vm.prank(delegator);
      (uint256 claimedRewards,) = nftStakingManager.claimDelegatorRewards(delegationID2, 1);

      assertEq(claimedRewards, epochRewards);
    }

    // after staking 2 tokenIds for separate days, the prepayment should be down to 1 day remaining
    assertEq(nftStakingManager.getPrepaidCredits(hardwareProvider, delegator), 1 days);
  }

  function test_setPrepaidCredits0() public {
    address hardwareProvider = getActor("HardwareProvider");
    vm.startPrank(admin);
    nftStakingManager.grantRole(nftStakingManager.PREPAYMENT_ROLE(), hardwareProvider);
    vm.stopPrank();

    address delegator = getActor("Delegator");

    uint32 initialCredits = uint32(5 * EPOCH_DURATION); // 5 days worth
    vm.prank(hardwareProvider);
    nftStakingManager.setPrepaidCredits(hardwareProvider, delegator, initialCredits);

    assertEq(
      nftStakingManager.getPrepaidCredits(hardwareProvider, delegator),
      initialCredits,
      "Initial credits should match"
    );

    vm.prank(hardwareProvider);
    nftStakingManager.setPrepaidCredits(hardwareProvider, delegator, 0);

    assertEq(
      nftStakingManager.getPrepaidCredits(hardwareProvider, delegator),
      0,
      "Credits should be reset to zero"
    );
  }

  function test_setPrepaidCredits_unauthorized() public {
    address hardwareProvider = getActor("HardwareProvider");
    address unauthorized = getActor("Unauthorized");
    address delegator = getActor("Delegator");

    // Grant role to hardware provider
    vm.startPrank(admin);
    nftStakingManager.grantRole(nftStakingManager.PREPAYMENT_ROLE(), hardwareProvider);
    vm.stopPrank();

    // Try to set credits without role
    vm.startPrank(unauthorized);
    vm.expectRevert();
    nftStakingManager.setPrepaidCredits(hardwareProvider, delegator, uint32(5 * EPOCH_DURATION));
    vm.stopPrank();
  }

  function test_getPrepaidCredits_nonExistent() public {
    address hardwareProvider = getActor("HardwareProvider");
    address delegator = getActor("Delegator");

    // Should return 0 for non-existent credits
    uint256 credits = nftStakingManager.getPrepaidCredits(hardwareProvider, delegator);
    assertEq(credits, 0, "Non-existent credits should return 0");
  }
}
