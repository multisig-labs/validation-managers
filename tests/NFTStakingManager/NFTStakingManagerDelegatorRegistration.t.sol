// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

import {
  DelegationInfoView,
  NFTStakingManager,
  ValidationInfoView
} from "../../contracts/NFTStakingManager.sol";
import { NFTStakingManagerBase } from "../utils/NFTStakingManagerBase.sol";
import {
  Validator,
  ValidatorStatus
} from "icm-contracts-2.0.0/contracts/validator-manager/interfaces/IACP99Manager.sol";

contract NFTStakingManagerDelegatorRegistrationTest is NFTStakingManagerBase {
  //
  // DELEGATOR REGISTRATION
  //
  function test_initiateDelegatorRegistration_base() public {
    (bytes32 validationID, address validator) = _createValidator();

    address delegator = getActor("Delegator");
    uint256[] memory tokenIDs = new uint256[](1);
    tokenIDs[0] = nft.mint(delegator);

    // we need to prepay for these too
    vm.prank(validator);
    nftStakingManager.setPrepaidCredits(validator, delegator, uint32(1 days));

    vm.startPrank(delegator);
    bytes32 delegationID = nftStakingManager.initiateDelegatorRegistration(validationID, tokenIDs);
    vm.stopPrank();

    DelegationInfoView memory delegation = nftStakingManager.getDelegationInfoView(delegationID);
    assertEq(delegation.owner, delegator);
    assertEq(delegation.tokenIDs.length, 1);
    assertEq(delegation.tokenIDs[0], 1);
    assertEq(delegation.validationID, validationID);

    nftStakingManager.completeDelegatorRegistration(delegationID, 0);

    delegation = nftStakingManager.getDelegationInfoView(delegationID);
    assertEq(delegation.startEpoch, nftStakingManager.getEpochByTimestamp(block.timestamp));

    ValidationInfoView memory validation = nftStakingManager.getValidationInfoView(validationID);
    assertEq(validation.licenseCount, 1);

    Validator memory v = validatorManager.getValidator(validationID);
    assertEq(v.weight, NODE_LICENSE_WEIGHT);
  }

  function test_initiateDelegatorRegistrationByOperator_default() public {
    // Create validator
    (bytes32 validationID, address validator) = _createValidator();

    // Create delegator and mint tokens
    address delegator = getActor("Delegator");
    uint256[] memory tokenIDs = new uint256[](1);
    tokenIDs[0] = nft.mint(delegator);

    // Delegator approves validator as operator
    vm.startPrank(delegator);
    nft.setDelegationApprovalForAll(validator, true);
    vm.stopPrank();

    // Call the new function as the hardware provider
    vm.startPrank(validator);
    bytes32 delegationID =
      nftStakingManager.initiateDelegatorRegistrationOnBehalfOf(validationID, delegator, tokenIDs);
    vm.stopPrank();

    // Verify the delegation was created correctly
    DelegationInfoView memory delegation = nftStakingManager.getDelegationInfoView(delegationID);
    assertEq(delegation.owner, delegator);
    assertEq(delegation.tokenIDs.length, 1);
    assertEq(delegation.tokenIDs[0], tokenIDs[0]);
    assertEq(delegation.validationID, validationID);

    // Complete the registration
    nftStakingManager.completeDelegatorRegistration(delegationID, 0);

    // Verify the delegation is active
    delegation = nftStakingManager.getDelegationInfoView(delegationID);
    assertEq(delegation.startEpoch, nftStakingManager.getEpochByTimestamp(block.timestamp));

    // Verify the validator's license count
    ValidationInfoView memory validation = nftStakingManager.getValidationInfoView(validationID);
    assertEq(validation.licenseCount, 1);
  }

  function test_initiateDelegatorRegistrationOnBehalfOf_unauthorized() public {
    // Create validator
    (bytes32 validationID, address validator) = _createValidator();

    // Create delegator and mint tokens
    address delegator = getActor("Delegator");
    uint256[] memory tokenIDs = new uint256[](1);
    tokenIDs[0] = nft.mint(delegator);

    // Try to call without operator approval
    vm.startPrank(validator);
    vm.expectRevert(NFTStakingManager.UnauthorizedOwner.selector);
    nftStakingManager.initiateDelegatorRegistrationOnBehalfOf(validationID, delegator, tokenIDs);
    vm.stopPrank();

    // Approve operator
    vm.startPrank(delegator);
    nft.setDelegationApprovalForAll(validator, true);
    vm.stopPrank();

    // Try with wrong validator
    address otherValidator = getActor("OtherValidator");
    vm.startPrank(otherValidator);
    vm.expectRevert(NFTStakingManager.UnauthorizedOwner.selector);
    nftStakingManager.initiateDelegatorRegistrationOnBehalfOf(validationID, delegator, tokenIDs);
    vm.stopPrank();
  }

  function test_initiateDelegatorRegistrationOnBehalfOf_individualApprovals() public {
    // Create validator
    (bytes32 validationID, address validator) = _createValidator();

    // Create delegator and mint multiple tokens
    address delegator = getActor("Delegator");
    uint256[] memory tokenIDs = new uint256[](2);
    tokenIDs[0] = nft.mint(delegator);
    tokenIDs[1] = nft.mint(delegator);

    // Approve validator for specific tokens
    vm.startPrank(delegator);
    nft.approveDelegation(validator, tokenIDs[0]);
    nft.approveDelegation(validator, tokenIDs[1]);
    vm.stopPrank();

    // Call the new function as the hardware provider
    vm.startPrank(validator);
    bytes32 delegationID =
      nftStakingManager.initiateDelegatorRegistrationOnBehalfOf(validationID, delegator, tokenIDs);
    vm.stopPrank();

    // Verify the delegation was created correctly
    DelegationInfoView memory delegation = nftStakingManager.getDelegationInfoView(delegationID);
    assertEq(delegation.owner, delegator);
    assertEq(delegation.tokenIDs.length, 2);
    assertEq(delegation.tokenIDs[0], tokenIDs[0]);
    assertEq(delegation.tokenIDs[1], tokenIDs[1]);
    assertEq(delegation.validationID, validationID);
  }

  function test_initiateDelegatorRegistrationOnBehalfOf_mixedApprovals() public {
    // Create validator
    (bytes32 validationID, address validator) = _createValidator();

    // Create delegator and mint multiple tokens
    address delegator = getActor("Delegator");
    uint256[] memory tokenIDs = new uint256[](3);
    tokenIDs[0] = nft.mint(delegator);
    tokenIDs[1] = nft.mint(delegator);
    tokenIDs[2] = nft.mint(delegator);

    // Mixed approval approach
    vm.startPrank(delegator);
    nft.approve(validator, tokenIDs[0]); // Individual approval for first token
    nft.setDelegationApprovalForAll(validator, true); // Blanket approval for all tokens
    vm.stopPrank();

    // Call the new function as the hardware provider
    vm.startPrank(validator);
    bytes32 delegationID =
      nftStakingManager.initiateDelegatorRegistrationOnBehalfOf(validationID, delegator, tokenIDs);
    vm.stopPrank();

    // Verify the delegation was created correctly
    DelegationInfoView memory delegation = nftStakingManager.getDelegationInfoView(delegationID);
    assertEq(delegation.owner, delegator);
    assertEq(delegation.tokenIDs.length, 3);
    assertEq(delegation.tokenIDs[0], tokenIDs[0]);
    assertEq(delegation.tokenIDs[1], tokenIDs[1]);
    assertEq(delegation.tokenIDs[2], tokenIDs[2]);
    assertEq(delegation.validationID, validationID);
  }

  function test_delegatorJoinsLate_noRewards() public {
    (bytes32 validationID,) = _createValidator();

    uint32 currentEpoch = nftStakingManager.getEpochByTimestamp(block.timestamp);
    uint32 epochEndTime = nftStakingManager.getEpochEndTime(currentEpoch - 1); // currentEpoch is 1-indexed, getEpochEndTime expects 0-indexed or current epoch number
    uint32 halfwayThroughEpoch = epochEndTime + (EPOCH_DURATION / 2);

    // Warp to after halfway through the current epoch
    vm.warp(halfwayThroughEpoch + 1 seconds);

    (bytes32 delegationID,) = _createDelegation(validationID, 1);

    DelegationInfoView memory d = nftStakingManager.getDelegationInfoView(delegationID);
    // Start epoch should be the next epoch
    assertEq(d.startEpoch, currentEpoch + 1, "Delegator start epoch should be next epoch");

    // Process proof for the current epoch
    _warpToGracePeriod(currentEpoch);
    _processUptimeProof(validationID, EPOCH_DURATION * 90 / 100);

    // Mint rewards for the current epoch
    _warpAfterGracePeriod(currentEpoch);
    _mintOneReward(validationID, currentEpoch);

    // Verify delegator has no rewards for the current epoch
    uint256 rewards = nftStakingManager.getRewardsForEpoch(delegationID, currentEpoch);
    assertEq(rewards, 0, "Delegator should have no rewards for the current epoch");

    // Verify delegator has rewards for the next epoch if they stay
    uint32 nextEpoch = currentEpoch + 1;
    _warpToGracePeriod(nextEpoch);
    _processUptimeProof(validationID, EPOCH_DURATION * 2 * 90 / 100); // Uptime for 2 epochs worth
    _warpAfterGracePeriod(nextEpoch);
    _mintOneReward(validationID, nextEpoch);

    rewards = nftStakingManager.getRewardsForEpoch(delegationID, nextEpoch);
    assertGt(rewards, 0, "Delegator should have rewards for the next epoch");
  }

  function test_delegatorJoinsEarly_leavesLate_rewards() public {
    // this function should test that a delegator joins early in the cycle, their
    // start epoch is set, they complete delegation removal
    // and still get rewards at the end of the cycle
    (bytes32 validationID,) = _createValidator();
    uint32 joinEpoch = nftStakingManager.getEpochByTimestamp(block.timestamp);

    // Delegator joins early in the current epoch
    uint32 epochStartTime = nftStakingManager.getEpochEndTime(joinEpoch - 1);
    vm.warp(epochStartTime + 10 seconds); // Join 10 seconds into the epoch

    (bytes32 delegationID, address delegator) = _createDelegation(validationID, 1);

    DelegationInfoView memory delegation = nftStakingManager.getDelegationInfoView(delegationID);
    assertEq(delegation.startEpoch, joinEpoch, "Delegator start epoch should be current epoch");

    // Delegator initiates removal late in the same epoch (after grace period would have ended, but before next epoch starts)
    uint32 epochEndTime = nftStakingManager.getEpochEndTime(joinEpoch);
    vm.warp(epochEndTime - 10 seconds); // Leave 10 seconds before epoch ends

    bytes32[] memory delegationIDs = new bytes32[](1);
    delegationIDs[0] = delegationID;
    vm.startPrank(delegator);
    nftStakingManager.initiateDelegatorRemoval(delegationIDs);
    nftStakingManager.completeDelegatorRemoval(delegationID, 0);
    vm.stopPrank();

    // Process proof for the joinEpoch
    _warpToGracePeriod(joinEpoch);
    _processUptimeProof(validationID, EPOCH_DURATION * 90 / 100);

    // Mint rewards for the joinEpoch
    _warpAfterGracePeriod(joinEpoch);
    _mintOneReward(validationID, joinEpoch);

    // Verify delegator has rewards for the joinEpoch
    uint256 rewards = nftStakingManager.getRewardsForEpoch(delegationID, joinEpoch);
    assertGt(rewards, 0, "Delegator should have rewards for the epoch they joined and left late");

    // Claim rewards
    vm.prank(delegator);
    (uint256 totalRewards,) = nftStakingManager.claimDelegatorRewards(delegationID, 1);
    assertGt(totalRewards, 0, "Claimed rewards mismatch");
  }

  function test_initiateDelegatorRegistration_noTokens() public {
    (bytes32 validationID,) = _createValidator();
    address delegator = getActor("Delegator");
    uint256[] memory tokenIDs = new uint256[](0);

    vm.startPrank(delegator);
    vm.expectRevert(NFTStakingManager.NoTokenIDsProvided.selector);
    nftStakingManager.initiateDelegatorRegistration(validationID, tokenIDs);
    vm.stopPrank();
  }

  function test_initiateDelegatorRegistration_unauthorizedOwner() public {
    (bytes32 validationID,) = _createValidator();
    address delegator = getActor("Delegator");
    address unauthorized = getActor("Unauthorized");

    uint256[] memory tokenIDs = new uint256[](1);
    tokenIDs[0] = nft.mint(delegator);

    vm.startPrank(unauthorized);
    vm.expectRevert(NFTStakingManager.UnauthorizedOwner.selector);
    nftStakingManager.initiateDelegatorRegistration(validationID, tokenIDs);
    vm.stopPrank();
  }

  function test_initiateDelegatorRegistration_validatorNotActive() public {
    address validator = getActor("Validator");
    uint256 hardwareTokenId = hardwareNft.mint(validator);

    // Initiate but don't complete validator registration
    vm.startPrank(validator);
    bytes32 validationID = nftStakingManager.initiateValidatorRegistration(
      DEFAULT_NODE_ID,
      DEFAULT_BLS_PUBLIC_KEY,
      DEFAULT_BLS_POP,
      DEFAULT_P_CHAIN_OWNER,
      DEFAULT_P_CHAIN_OWNER,
      hardwareTokenId,
      DELEGATION_FEE_BIPS
    );
    vm.stopPrank();

    address delegator = getActor("Delegator");
    uint256[] memory tokenIDs = new uint256[](1);
    tokenIDs[0] = nft.mint(delegator);

    vm.startPrank(delegator);
    vm.expectRevert(NFTStakingManager.ValidatorRegistrationNotComplete.selector);
    nftStakingManager.initiateDelegatorRegistration(validationID, tokenIDs);
    vm.stopPrank();
  }
}
