// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

import { Base } from "./utils/Base.sol";

import {
  DelegationInfo,
  DelegationInfoView,
  EpochInfo,
  EpochInfoView,
  NFTStakingManager,
  NFTStakingManagerSettings,
  ValidationInfo,
  DelegatorStatus,
  ValidationInfoView
} from "../contracts/NFTStakingManager.sol";

import {
  PChainOwner,
  Validator,
  ValidatorStatus
} from "icm-contracts-d426c55/contracts/validator-manager/ACP99Manager.sol";

import { ERC721Mock } from "./mocks/ERC721Mock.sol";
import { NativeMinterMock } from "./mocks/NativeMinterMock.sol";
import { MockValidatorManager } from "./mocks/ValidatorManagerMock.sol";

import { IWarpMessenger, WarpMessage } from "./utils/IWarpMessenger.sol";

import { ERC1967Proxy } from "@openzeppelin-contracts-5.3.0/proxy/ERC1967/ERC1967Proxy.sol";
import { console2 } from "forge-std-1.9.6/src/console2.sol";
import { PChainOwner } from "icm-contracts-d426c55/contracts/validator-manager/ACP99Manager.sol";

import { ValidatorMessages } from
  "icm-contracts-d426c55/contracts/validator-manager/ValidatorMessages.sol";

contract NFTStakingManagerTest is Base {
  ERC721Mock public nft;
  ERC721Mock public hardwareNft;
  MockValidatorManager public validatorManager;
  NFTStakingManager public nftStakingManager;

  address public admin;

  uint256 public epochRewards = 1000 ether;
  uint16 public MAX_LICENSES_PER_VALIDATOR = 40;
  uint64 public LICENSE_WEIGHT = 1000;
  uint64 public HARDWARE_LICENSE_WEIGHT = 0;
  uint32 public GRACE_PERIOD = 1 hours;
  uint32 public DELEGATION_FEE_BIPS = 1000;
  address public constant WARP_PRECOMPILE_ADDRESS = 0x0200000000000000000000000000000000000005;
  uint32 public EPOCH_DURATION = 1 days;

  bytes32 public constant DEFAULT_SOURCE_BLOCKCHAIN_ID =
    bytes32(hex"abcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcd");

  function setUp() public override {
    super.setUp();
    admin = getActor("Admin");

    validatorManager = new MockValidatorManager();

    nft = new ERC721Mock("NFT License", "NFTL");
    hardwareNft = new ERC721Mock("Hardware NFT License", "HARDNFTL");

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

    NativeMinterMock nativeMinter = new NativeMinterMock();
    vm.etch(0x0200000000000000000000000000000000000001, address(nativeMinter).code);
  }

  function _defaultNFTStakingManagerSettings(
    address validatorManager_,
    address license_,
    address hardwareLicense_
  ) internal view returns (NFTStakingManagerSettings memory) {
    return NFTStakingManagerSettings({
      admin: admin,
      validatorManager: validatorManager_,
      license: license_,
      hardwareLicense: hardwareLicense_,
      initialEpochTimestamp: uint32(block.timestamp),
      epochDuration: EPOCH_DURATION,
      licenseWeight: LICENSE_WEIGHT,
      hardwareLicenseWeight: HARDWARE_LICENSE_WEIGHT,
      epochRewards: epochRewards,
      maxLicensesPerValidator: MAX_LICENSES_PER_VALIDATOR,
      gracePeriod: GRACE_PERIOD,
      uptimePercentage: 80,
      bypassUptimeCheck: false
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
  function test_initiateDelegatorRegistration() public {
    (bytes32 validationID, address validator) = _createValidator();

    address delegator = getActor("Delegator");
    uint256[] memory tokenIDs = new uint256[](1);
    tokenIDs[0] = nft.mint(delegator);

    // we need to prepay for these too
    vm.prank(validator);
    nftStakingManager.addPrepaidCredits(delegator, uint32(1 days));

    vm.startPrank(delegator);
    bytes32 delegationID = nftStakingManager.initiateDelegatorRegistration(validationID, tokenIDs);
    vm.stopPrank();

    DelegationInfoView memory delegation = nftStakingManager.getDelegationInfoView(delegationID);
    assertEq(delegation.owner, delegator);
    assertEq(delegation.tokenIDs.length, 1);
    assertEq(delegation.tokenIDs[0], 0);
    assertEq(delegation.validationID, validationID);

    nftStakingManager.completeDelegatorRegistration(delegationID, 0);

    delegation = nftStakingManager.getDelegationInfoView(delegationID);
    assertEq(delegation.startEpoch, nftStakingManager.getEpochByTimestamp(block.timestamp));

    ValidationInfoView memory validation = nftStakingManager.getValidationInfoView(validationID);
    assertEq(validation.licenseCount, 1);

    Validator memory v = validatorManager.getValidator(validationID);
    assertEq(v.weight, LICENSE_WEIGHT);
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
    nft.setApprovalForAll(validator, true);
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
    nft.setApprovalForAll(validator, true);
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
    nft.approve(validator, tokenIDs[0]);
    nft.approve(validator, tokenIDs[1]);
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
    nft.setApprovalForAll(validator, true); // Blanket approval for all tokens
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

  //
  // DELEGATOR REMOVAL
  //
  function test_initiateDelegatorRemoval_multiple() public {
    (bytes32 validationID, address validator) = _createValidator();
    // I want a function that creates multiple delegations
    bytes32[] memory delegationIDs = _createMultipleDelegations(validationID, validator, 20);

    vm.startPrank(validator);
    startMeasuringGas("initiateDelegatorRemoval");
    nftStakingManager.initiateDelegatorRemoval(delegationIDs);
    stopMeasuringGas();
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
    nftStakingManager.addPrepaidCredits(delegator, uint32(epochDuration * 2));

    bytes memory uptimeMessage =
      ValidatorMessages.packValidationUptimeMessage(validationID, uint64(epoch1UptimeSeconds));
    _mockGetUptimeWarpMessage(uptimeMessage, true, uint32(0));
    vm.expectRevert(NFTStakingManager.EpochHasNotEnded.selector);
    nftStakingManager.processProof(uint32(0));

    vm.warp(epoch1AfterGracePeriod);
    uptimeMessage =
      ValidatorMessages.packValidationUptimeMessage(validationID, uint64(epoch1UptimeSeconds));
    _mockGetUptimeWarpMessage(uptimeMessage, true, uint32(0));
    vm.expectRevert(NFTStakingManager.GracePeriodHasPassed.selector);
    nftStakingManager.processProof(uint32(0));

    vm.warp(epoch1InGracePeriod);
    uptimeMessage =
      ValidatorMessages.packValidationUptimeMessage(validationID, uint64(epoch1UptimeSeconds));
    _mockGetUptimeWarpMessage(uptimeMessage, true, uint32(0));
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
      nftStakingManager.claimRewards(delegationID, 2);

    assertEq(totalRewards, epochRewards * 2);
    assertEq(claimedEpochNumbers.length, 2);
    assertEq(claimedEpochNumbers[0], rewardsEpoch - 1);
    assertEq(claimedEpochNumbers[1], rewardsEpoch);
  }

  function test_processProof_insufficientUptime() public {
    uint256 startTime = block.timestamp;
    uint256 epochDuration = 1 days;

    (bytes32 validationID,) = _createValidator();
    _createDelegation(validationID, 1);

    // Move to the grace period of the first epoch
    vm.warp(startTime + epochDuration + GRACE_PERIOD / 2);

    uint256 insufficientUptime = epochDuration * 70 / 100;

    bytes memory uptimeMessage =
      ValidatorMessages.packValidationUptimeMessage(validationID, uint64(insufficientUptime));
    _mockGetUptimeWarpMessage(uptimeMessage, true, uint32(0));
    vm.expectRevert(NFTStakingManager.InsufficientUptime.selector);
    nftStakingManager.processProof(uint32(0));
  }

  function test_processProof_missUptime() public {
    uint256 startTime =
      nftStakingManager.getEpochEndTime(nftStakingManager.getEpochByTimestamp(block.timestamp) - 1);
    uint256 epochDuration = 1 days;

    (bytes32 validationID, address validator) = _createValidator();
    (bytes32 delegationID, address delegator) = _createDelegation(validationID, 1);

    vm.prank(validator);
    nftStakingManager.addPrepaidCredits(delegator, uint32(epochDuration * 2));

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
    nftStakingManager.addPrepaidCredits(delegator, 1 days);

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
    nftStakingManager.addPrepaidCredits(delegator, 10 days);

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
    nftStakingManager.addPrepaidCredits(delegator, 5 days);

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
    nftStakingManager.addPrepaidCredits(delegator1, uint32(1 days));
    nftStakingManager.addPrepaidCredits(delegator2, uint32(2 days));
    nftStakingManager.addPrepaidCredits(delegator3, uint32(3 days));
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
      nftStakingManager.addPrepaidCredits(delegator, uint32(5 * EPOCH_DURATION)); // Prepay for 5 days

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
      (uint256 claimedRewards,) = nftStakingManager.claimRewards(delegationID1, 1);
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
      (uint256 claimedRewards,) = nftStakingManager.claimRewards(delegationID2, 1);

      assertEq(claimedRewards, epochRewards);
    }

    // after staking 2 tokenIds for separate days, the prepayment should be down to 1 day remaining
    assertEq(nftStakingManager.getPrepaidCredits(hardwareProvider, delegator), 1 days);
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
    nftStakingManager.addPrepaidCredits(delegator1, uint32(1 days));
    nftStakingManager.addPrepaidCredits(delegator2, uint32(1 days));
    vm.stopPrank();

    // First delegator initiates registration, should get a lower nonce number
    vm.prank(delegator1);
    bytes32 delegationID1 = nftStakingManager.initiateDelegatorRegistration(validationID, tokenIDs1);

    DelegationInfoView memory delegation1 = nftStakingManager.getDelegationInfoView(delegationID1);
    uint64 firstNonce = delegation1.startingNonce;
    
    Validator memory v = validatorManager.getValidator(validationID);
    assertEq(v.weight, LICENSE_WEIGHT);
    assertEq(v.sentNonce, firstNonce);
    assertEq(v.receivedNonce, 0);

    // Second delegator initiates registration, should get another nonce number that's higher
    vm.prank(delegator2);
    bytes32 delegationID2 = nftStakingManager.initiateDelegatorRegistration(validationID, tokenIDs2);

    DelegationInfoView memory delegation2 = nftStakingManager.getDelegationInfoView(delegationID2);
    uint64 secondNonce = delegation2.startingNonce;
    
    v = validatorManager.getValidator(validationID);
    assertEq(v.weight, LICENSE_WEIGHT * 2);
    assertEq(v.sentNonce, secondNonce);
    assertEq(v.receivedNonce, 0);
    
    
    // Complete weight update for second delegation
    nftStakingManager.completeDelegatorRegistration(delegationID2, uint32(0));
    
    v = validatorManager.getValidator(validationID);
    assertEq(v.weight, LICENSE_WEIGHT * 2);
    assertEq(v.receivedNonce, secondNonce);
    
    
    nftStakingManager.completeDelegatorRegistration(delegationID1, uint32(0));

    v = validatorManager.getValidator(validationID);
    
    assertEq(v.weight, LICENSE_WEIGHT * 2);
    assertEq(v.receivedNonce, secondNonce);



    // Verify both delegations are active
    delegation1 = nftStakingManager.getDelegationInfoView(delegationID1);
    delegation2 = nftStakingManager.getDelegationInfoView(delegationID2);
    assertEq(uint8(delegation1.status), uint8(DelegatorStatus.Active));
    assertEq(uint8(delegation2.status), uint8(DelegatorStatus.Active));
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
    vm.startPrank(delegator);
    bytes32 delegationID = nftStakingManager.initiateDelegatorRegistration(
      validationID, nft.batchMint(delegator, licenseCount)
    );
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
