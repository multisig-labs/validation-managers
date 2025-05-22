// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

import { Base } from "./utils/Base.sol";

import {
  DelegationInfo,
  DelegationInfoView,
  DelegatorStatus,
  EpochInfo,
  EpochInfoView,
  NFTStakingManager,
  NFTStakingManagerSettings,
  ValidationInfo,
  ValidationInfoView
} from "../contracts/NFTStakingManager.sol";

import { NodeLicense, NodeLicenseSettings } from "../contracts/tokens/NodeLicense.sol";

import {
  PChainOwner,
  Validator,
  ValidatorStatus
} from "icm-contracts-2.0.0/contracts/validator-manager/interfaces/IACP99Manager.sol";

import { ERC721Mock } from "./mocks/ERC721Mock.sol";
import { NativeMinterMock } from "./mocks/NativeMinterMock.sol";
import { MockValidatorManager } from "./mocks/ValidatorManagerMock.sol";

import { IWarpMessenger, WarpMessage } from "./utils/IWarpMessenger.sol";

import { ERC1967Proxy } from "@openzeppelin-contracts-5.3.0/proxy/ERC1967/ERC1967Proxy.sol";
import { console2 } from "forge-std-1.9.6/src/console2.sol";
import { PChainOwner } from "icm-contracts-2.0.0/contracts/validator-manager/ACP99Manager.sol";

import { ValidatorMessages } from
  "icm-contracts-2.0.0/contracts/validator-manager/ValidatorMessages.sol";

contract NFTStakingManagerTest is Base {
  NodeLicense public nft;
  ERC721Mock public hardwareNft;
  MockValidatorManager public validatorManager;
  NFTStakingManager public nftStakingManager;

  address public admin;

  uint256 public epochRewards = 1000 ether;
  uint16 public MAX_LICENSES_PER_VALIDATOR = 40;
  uint64 public NODE_LICENSE_WEIGHT = 1000;
  uint64 public HARDWARE_LICENSE_WEIGHT = 0;
  uint32 public GRACE_PERIOD = 1 hours;
  uint32 public DELEGATION_FEE_BIPS = 1000;
  address public constant WARP_PRECOMPILE_ADDRESS = 0x0200000000000000000000000000000000000005;
  uint32 public EPOCH_DURATION = 1 days;
  uint256 public BIPS_CONVERSION_FACTOR = 10000;

  bytes32 public constant DEFAULT_SOURCE_BLOCKCHAIN_ID =
    bytes32(hex"abcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcd");

  function setUp() public override {
    super.setUp();
    admin = getActor("Admin");
    vm.startPrank(admin);

    validatorManager = new MockValidatorManager();

    hardwareNft = new ERC721Mock("Hardware NFT License", "HARDNFTL");

    NodeLicense nodeLicenseImpl = new NodeLicense();
    ERC1967Proxy nodeLicenseProxy = new ERC1967Proxy(
      address(nodeLicenseImpl),
      abi.encodeCall(
        NodeLicense.initialize,
        NodeLicenseSettings({
          name: "NFT License",
          symbol: "NFTL",
          admin: admin,
          minter: address(this),
          nftStakingManager: address(nftStakingManager),
          baseTokenURI: "https://example.com/nft/",
          unlockTime: 0,
          defaultAdminDelay: 0
        })
      )
    );
    nft = NodeLicense(address(nodeLicenseProxy));

    NFTStakingManager stakingManagerImpl = new NFTStakingManager();
    ERC1967Proxy stakingManagerProxy = new ERC1967Proxy(
      address(stakingManagerImpl),
      abi.encodeCall(
        NFTStakingManager.initialize,
        _defaultNFTStakingManagerSettings(
          address(validatorManager), address(nft), address(hardwareNft)
        )
      )
    );
    nftStakingManager = NFTStakingManager(address(stakingManagerProxy));

    nft.setNFTStakingManager(address(nftStakingManager));

    NativeMinterMock nativeMinter = new NativeMinterMock();
    vm.etch(0x0200000000000000000000000000000000000001, address(nativeMinter).code);

    vm.stopPrank();
  }

  //
  // INITIALIZATION
  //
  function test_initialization_defaultSettings() public view {
    NFTStakingManagerSettings memory expectedSettings = _defaultNFTStakingManagerSettings(
      address(validatorManager), address(nft), address(hardwareNft)
    );

    NFTStakingManagerSettings memory actualSettings = nftStakingManager.getSettings();

    assertEq(
      actualSettings.validatorManager,
      expectedSettings.validatorManager,
      "validatorManager mismatch"
    );
    assertEq(actualSettings.nodeLicense, expectedSettings.nodeLicense, "license mismatch");
    assertEq(
      actualSettings.hardwareLicense, expectedSettings.hardwareLicense, "hardwareLicense mismatch"
    );
    assertEq(
      actualSettings.initialEpochTimestamp,
      expectedSettings.initialEpochTimestamp,
      "initialEpochTimestamp mismatch"
    );
    assertEq(actualSettings.epochDuration, expectedSettings.epochDuration, "epochDuration mismatch");
    assertEq(
      actualSettings.nodeLicenseWeight,
      expectedSettings.nodeLicenseWeight,
      "nodeLicenseWeight mismatch"
    );
    assertEq(
      actualSettings.hardwareLicenseWeight,
      expectedSettings.hardwareLicenseWeight,
      "hardwareLicenseWeight mismatch"
    );
    assertEq(actualSettings.epochRewards, expectedSettings.epochRewards, "epochRewards mismatch");
    assertEq(
      actualSettings.maxLicensesPerValidator,
      expectedSettings.maxLicensesPerValidator,
      "maxLicensesPerValidator mismatch"
    );
    assertEq(actualSettings.gracePeriod, expectedSettings.gracePeriod, "gracePeriod mismatch");
    assertEq(
      actualSettings.uptimePercentageBips,
      expectedSettings.uptimePercentageBips,
      "uptimePercentageBips mismatch"
    );
    assertEq(
      actualSettings.bypassUptimeCheck,
      expectedSettings.bypassUptimeCheck,
      "bypassUptimeCheck mismatch"
    );
    assertEq(
      actualSettings.minDelegationEpochs,
      expectedSettings.minDelegationEpochs,
      "minDelegationEpochs mismatch"
    );
  }

  function _defaultNFTStakingManagerSettings(
    address validatorManager_,
    address nodeLicense_,
    address hardwareLicense_
  ) internal view returns (NFTStakingManagerSettings memory) {
    return NFTStakingManagerSettings({
      validatorManager: validatorManager_,
      nodeLicense: nodeLicense_,
      hardwareLicense: hardwareLicense_,
      initialEpochTimestamp: uint32(block.timestamp),
      epochDuration: EPOCH_DURATION,
      nodeLicenseWeight: NODE_LICENSE_WEIGHT,
      hardwareLicenseWeight: HARDWARE_LICENSE_WEIGHT,
      epochRewards: epochRewards,
      maxLicensesPerValidator: MAX_LICENSES_PER_VALIDATOR,
      gracePeriod: GRACE_PERIOD,
      uptimePercentageBips: 8000,
      bypassUptimeCheck: false,
      minDelegationEpochs: 0
    });
  }

  //
  // VALIDATOR REGISTRATION
  //
  function test_initiateValidatorRegistration() public {
    address validator = getActor("Validator");
    uint256 hardwareTokenId = hardwareNft.mint(validator);
    uint32 currentEpoch = nftStakingManager.getEpochByTimestamp(block.timestamp);

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

    Validator memory v = validatorManager.getValidator(validationID);

    assertEq(hardwareNft.balanceOf(validator), 1);
    assertEq(uint8(v.status), uint8(ValidatorStatus.PendingAdded));
    assertEq(v.weight, HARDWARE_LICENSE_WEIGHT);

    assertEq(nftStakingManager.getValidationIDs().length, 1);
    assertEq(nftStakingManager.getValidationIDs()[0], validationID);

    ValidationInfoView memory validationInfoView =
      nftStakingManager.getValidationInfoView(validationID);
    assertEq(validationInfoView.startEpoch, 0);
    assertEq(validationInfoView.delegationFeeBips, DELEGATION_FEE_BIPS);
    assertEq(validationInfoView.owner, validator);
    assertEq(validationInfoView.hardwareTokenID, hardwareTokenId);

    nftStakingManager.completeValidatorRegistration(0);

    v = validatorManager.getValidator(validationID);
    validationInfoView = nftStakingManager.getValidationInfoView(validationID);
    assertEq(uint8(v.status), uint8(ValidatorStatus.Active));
    assertEq(validationInfoView.startEpoch, currentEpoch);
  }

  //
  // VALIDATOR REMOVAL
  //
  function test_initiateValidatorRemoval() public {
    (bytes32 validationID, address validator) = _createValidator();
    (bytes32 delegationID,) = _createDelegation(validationID, 1);

    address otherAddress = getActor("OtherAddress");
    vm.startPrank(otherAddress);
    vm.expectRevert(NFTStakingManager.UnauthorizedOwner.selector);
    nftStakingManager.initiateValidatorRemoval(validationID);
    vm.stopPrank();

    uint32 currentEpoch = nftStakingManager.getEpochByTimestamp(block.timestamp);

    bytes32[] memory delegationIDs = new bytes32[](1);
    delegationIDs[0] = delegationID;

    vm.startPrank(validator);
    vm.expectRevert(NFTStakingManager.ValidatorHasActiveDelegations.selector);
    nftStakingManager.initiateValidatorRemoval(validationID);

    nftStakingManager.initiateDelegatorRemoval(delegationIDs);
    nftStakingManager.initiateValidatorRemoval(validationID);

    ValidationInfoView memory validationInfo = nftStakingManager.getValidationInfoView(validationID);
    assertEq(validationInfo.endEpoch, currentEpoch);

    Validator memory v = validatorManager.getValidator(validationID);

    assertEq(uint8(v.status), uint8(ValidatorStatus.PendingRemoved));
  }

  function test_completeValidatorRemoval() public {
    // Create validator and initiate removal
    address validator = getActor("Validator");
    uint256 hardwareTokenId = hardwareNft.mint(validator);

    (bytes32 validationID,) = _createValidator(validator, hardwareTokenId);
    (bytes32 delegationID,) = _createDelegation(validationID, 1);

    vm.startPrank(validator);
    vm.expectRevert(NFTStakingManager.ValidatorHasActiveDelegations.selector);
    nftStakingManager.initiateValidatorRemoval(validationID);
    vm.stopPrank();

    bytes32[] memory delegationIDs = new bytes32[](1);
    delegationIDs[0] = delegationID;

    vm.prank(validator);
    nftStakingManager.initiateDelegatorRemoval(delegationIDs);

    vm.prank(validator);
    nftStakingManager.initiateValidatorRemoval(validationID);

    // Complete the removal
    nftStakingManager.completeValidatorRemoval(0);

    // Verify validator is removed from the list
    // bytes32[] memory validationIDs = nftStakingManager.getValidationIDs();
    // assertEq(validationIDs.length, 0);

    // Verify hardware token is unlocked
    assertEq(nftStakingManager.getHardwareTokenLockedBy(hardwareTokenId), bytes32(0));

    Validator memory v = validatorManager.getValidator(validationID);

    // Verify validator manager state
    assertEq(uint8(v.status), uint8(ValidatorStatus.Completed));
  }

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
    nftStakingManager.addPrepaidCredits(validator, delegator, uint32(1 days));

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

  function test_delegatorJoinsEarly_leavesDuringGracePeriod_rewards() public {
    // this funciton should test that a delegator joins early in the cycle,
    // start epoch is this epoch, they leave during the grace period and still get rewards
  }

  function test_delegatorSwitchValidator_singleRewards() public {
    // this function should test that a delegator joins early in one epoch,
    // then leaves during the next epoch and switches to a different validator
    // they should get rewards from the first validator on the first epoch,
    // and rewards from the second validator on the second epoch
  }

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
    nftStakingManager.completeDelegatorRemoval(delegationID, 0);

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

  //
  // PROOF PROCESSING
  //
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
    nftStakingManager.addPrepaidCredits(validator, delegator, uint32(epochDuration * 2));

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
    nftStakingManager.addPrepaidCredits(validator, delegator, uint32(epochDuration * 2));

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
    nftStakingManager.addPrepaidCredits(
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
    nftStakingManager.addPrepaidCredits(validator, delegator, 1 days);

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
    nftStakingManager.addPrepaidCredits(validator, delegator, 10 days);

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
    nftStakingManager.addPrepaidCredits(validator, delegator, 5 days);

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
    nftStakingManager.addPrepaidCredits(validator, delegator1, uint32(1 days));
    nftStakingManager.addPrepaidCredits(validator, delegator2, uint32(2 days));
    nftStakingManager.addPrepaidCredits(validator, delegator3, uint32(3 days));
    vm.stopPrank();

    // Create delegations with different token amounts
    bytes32 delegationId1 = _createDelegation(validationID, delegator1, 1);
    bytes32 delegationId2 = _createDelegation(validationID, delegator2, 2);
    bytes32 delegationId3 = _createDelegation(validationID, delegator3, 3);

    // Verify total staked licenses
    // assertEq(nftStakingManager.getCurrentTotalStakedLicenses(), 6);

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
      nftStakingManager.addPrepaidCredits(hardwareProvider, delegator, uint32(5 * EPOCH_DURATION)); // Prepay for 5 days

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
    // We are intentionally NOT calling addPrepaidCredits for delegator1 or delegator2.
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
    nftStakingManager.addPrepaidCredits(validator, delegator, uint32(2 * EPOCH_DURATION));

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
    nftStakingManager.addPrepaidCredits(validator, delegator1, uint32(1 days));
    nftStakingManager.addPrepaidCredits(validator, delegator2, uint32(1 days));
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
    nftStakingManager.addPrepaidCredits(validatorOwner, delegator1, uint32(1 * EPOCH_DURATION));
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
    nftStakingManager.addPrepaidCredits(validatorOwner, delegator2, uint32(1 * EPOCH_DURATION));
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
    nftStakingManager.addPrepaidCredits(validatorOwner, delegator3, uint32(1 * EPOCH_DURATION));
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

  function _mintOneReward(bytes32 validationID, uint32 epoch) internal {
    bytes32[] memory validationIDs = new bytes32[](1);
    validationIDs[0] = validationID;
    nftStakingManager.mintRewards(validationIDs, epoch);
  }

  function _createValidator() internal returns (bytes32, address) {
    address validator = getActor("Validator");
    uint256 hardwareTokenId = hardwareNft.mint(validator);

    return _createValidator(validator, hardwareTokenId);
  }

  function _createValidator(address validator, uint256 hardwareTokenId)
    internal
    returns (bytes32, address)
  {
    vm.startPrank(admin);
    nftStakingManager.grantRole(nftStakingManager.PREPAYMENT_ROLE(), validator);
    vm.stopPrank();

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
    nftStakingManager.completeValidatorRegistration(0);
    vm.stopPrank();

    return (validationID, validator);
  }

  function _processUptimeProof(bytes32 validationID, uint256 uptimeSeconds) internal {
    bytes memory uptimeMessage =
      ValidatorMessages.packValidationUptimeMessage(validationID, uint64(uptimeSeconds));
    _mockGetUptimeWarpMessage(uptimeMessage, true, uint32(0));
    nftStakingManager.processProof(uint32(0));
  }

  function _createMultipleDelegations(bytes32 validationID, address delegator, uint256 count)
    internal
    returns (bytes32[] memory delegationIDs)
  {
    delegationIDs = new bytes32[](count);
    for (uint256 i = 0; i < count; i++) {
      delegationIDs[i] = _createDelegation(validationID, delegator, 1);
    }
    return delegationIDs;
  }

  function _createDelegation(bytes32 validationID, address delegator, uint256 licenseCount)
    internal
    returns (bytes32)
  {
    uint256[] memory tokenIds = new uint256[](licenseCount);
    for (uint256 i = 0; i < licenseCount; i++) {
      tokenIds[i] = nft.mint(delegator);
    }

    vm.startPrank(delegator);
    bytes32 delegationID = nftStakingManager.initiateDelegatorRegistration(validationID, tokenIds);
    nftStakingManager.completeDelegatorRegistration(delegationID, 0);
    vm.stopPrank();
    return delegationID;
  }

  function _createDelegation(bytes32 validationID, address delegator, uint256[] memory tokenIds)
    internal
    returns (bytes32)
  {
    vm.startPrank(delegator);
    bytes32 delegationID = nftStakingManager.initiateDelegatorRegistration(validationID, tokenIds);
    nftStakingManager.completeDelegatorRegistration(delegationID, 0);
    vm.stopPrank();
    return delegationID;
  }

  function _createDelegation(bytes32 validationID, uint256 licenseCount)
    internal
    returns (bytes32, address)
  {
    address delegator = getActor("Delegator1");
    bytes32 delegationID = _createDelegation(validationID, delegator, licenseCount);
    return (delegationID, delegator);
  }

  function _warpToGracePeriod(uint32 epochNumber) internal {
    uint32 endTime = nftStakingManager.getEpochEndTime(epochNumber);
    vm.warp(endTime + GRACE_PERIOD / 2);
  }

  function _warpAfterGracePeriod(uint32 epochNumber) internal {
    uint32 endTime = nftStakingManager.getEpochEndTime(epochNumber);
    vm.warp(endTime + GRACE_PERIOD + 1);
  }

  function _mockGetUptimeWarpMessage(bytes memory expectedPayload, bool valid, uint32 index)
    internal
  {
    vm.mockCall(
      WARP_PRECOMPILE_ADDRESS,
      abi.encodeWithSelector(IWarpMessenger.getVerifiedWarpMessage.selector, index),
      abi.encode(
        WarpMessage({
          sourceChainID: 0x0000000000000000000000000000000000000000000000000000000000000000,
          originSenderAddress: address(0),
          payload: expectedPayload
        }),
        valid
      )
    );
    vm.expectCall(
      WARP_PRECOMPILE_ADDRESS, abi.encodeCall(IWarpMessenger.getVerifiedWarpMessage, index)
    );
  }
}
