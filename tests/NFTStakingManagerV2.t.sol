// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

import { Base } from "./utils/Base.sol";

import {
  DelegationInfo,
  DelegationInfoView,
  EpochInfo,
  NFTStakingManager,
  NFTStakingManagerSettings,
  ValidationInfo,
  ValidationInfoView
} from "../contracts/NFTStakingManagerV2.sol";
import { ERC721Mock } from "../contracts/mocks/ERC721Mock.sol";

import { NativeMinterMock } from "../contracts/mocks/NativeMinterMock.sol";
import { MockValidatorManager } from "../contracts/mocks/ValidatorManagerMock.sol";
import { IWarpMessenger, WarpMessage } from "./utils/IWarpMessenger.sol";

import { ERC1967Proxy } from "@openzeppelin-contracts-5.3.0/proxy/ERC1967/ERC1967Proxy.sol";
import { console2 } from "forge-std-1.9.6/src/console2.sol";
import { PChainOwner } from "icm-contracts-d426c55/contracts/validator-manager/ACP99Manager.sol";

contract NFTStakingManagerTest is Base {
  ERC721Mock public nft;
  ERC721Mock public hardwareNft;
  MockValidatorManager public validatorManager;
  NFTStakingManager public nftStakingManager;

  address public admin;

  uint256 public epochRewards = 1000 ether;
  uint16 public MAX_LICENSES_PER_VALIDATOR = 10;
  uint64 public LICENSE_WEIGHT = 1000;
  uint64 public HARDWARE_LICENSE_WEIGHT = 0;
  uint32 public GRACE_PERIOD = 1 hours;
  uint32 public DELEGATION_FEE_BIPS = 1000;

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
      epochDuration: 1 days,
      licenseWeight: LICENSE_WEIGHT,
      hardwareLicenseWeight: HARDWARE_LICENSE_WEIGHT,
      epochRewards: epochRewards,
      maxLicensesPerValidator: MAX_LICENSES_PER_VALIDATOR,
      requireHardwareTokenId: true,
      gracePeriod: GRACE_PERIOD,
      uptimePercentage: 80
    });
  }

  // okay this creates a validator that can take delegation
  // it should have available license slots
  // and a stake weight of 0
  function testv2_initiateValidatorRegistration() public {
    address validator = getActor("Validator");
    uint256 hardwareTokenId = hardwareNft.mint(validator);

    vm.startPrank(validator);
    bytes32 validationId = nftStakingManager.initiateValidatorRegistration(
      DEFAULT_NODE_ID,
      DEFAULT_BLS_PUBLIC_KEY,
      DEFAULT_BLS_POP,
      DEFAULT_P_CHAIN_OWNER,
      DEFAULT_P_CHAIN_OWNER,
      hardwareTokenId,
      DELEGATION_FEE_BIPS
    );
    vm.stopPrank();

    assertEq(hardwareNft.balanceOf(validator), 1);
    assertEq(validatorManager.created(validationId), true);
    assertEq(validatorManager.weights(validationId), HARDWARE_LICENSE_WEIGHT);

    assertEq(nftStakingManager.getValidationIds().length, 1);
    assertEq(nftStakingManager.getValidationIds()[0], validationId);

    nftStakingManager.completeValidatorRegistration(0);
    assertEq(validatorManager.validating(validationId), true);
  }

  function testv2_initiateDelegatorRegistration() public {
    (bytes32 validationId, address validator) = _createValidator();

    address delegator = getActor("Delegator");
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = nft.mint(delegator);

    // we need to prepay for these too
    vm.prank(admin);
    nftStakingManager.addPrepaidCredits(delegator, 1 days);

    vm.startPrank(delegator);
    bytes32 delegationId = nftStakingManager.initiateDelegatorRegistration(validationId, tokenIds);
    vm.stopPrank();

    DelegationInfoView memory delegation = nftStakingManager.getDelegationInfoView(delegationId);
    assertEq(delegation.owner, delegator);
    assertEq(delegation.tokenIds.length, 1);
    assertEq(delegation.tokenIds[0], 1);
    assertEq(delegation.validationId, validationId);

    nftStakingManager.completeDelegatorRegistration(delegationId, 0);

    delegation = nftStakingManager.getDelegationInfoView(delegationId);
    assertEq(delegation.startEpoch, nftStakingManager.getCurrentEpoch());

    ValidationInfoView memory validation = nftStakingManager.getValidationInfoView(validationId);
    assertEq(validation.licenseCount, 1);

    assertEq(validatorManager.weights(validationId), LICENSE_WEIGHT);
  }

  function test_processProof_base() public {
    uint256 startTime = block.timestamp;
    uint256 epochDuration = 1 days;

    uint256 epoch1InGracePeriod = startTime + epochDuration + GRACE_PERIOD / 2;
    uint256 epoch1AfterGracePeriod = startTime + epochDuration + GRACE_PERIOD;

    uint256 epoch2InGracePeriod = startTime + epochDuration * 2 + GRACE_PERIOD - 1;
    uint256 epoch2AfterGracePeriod = startTime + epochDuration * 2 + GRACE_PERIOD;

    uint256 epoch1UptimeSeconds = epochDuration * 90 / 100;
    uint256 epoch2UptimeSeconds = epoch1UptimeSeconds + epochDuration * 90 / 100;

    uint32 rewardsEpoch = nftStakingManager.getCurrentEpoch();
    (bytes32 validationId, address validator) = _createValidator();
    (bytes32 delegationId, address delegator) = _createDelegation(validationId, 1);

    vm.expectRevert("Epoch has not ended");
    nftStakingManager.processProof(validationId, epoch1UptimeSeconds);

    vm.warp(epoch1AfterGracePeriod);
    vm.expectRevert("Grace period has passed");
    nftStakingManager.processProof(validationId, epoch1UptimeSeconds);

    vm.warp(epoch1InGracePeriod);
    nftStakingManager.processProof(validationId, epoch1UptimeSeconds);

    EpochInfo memory epoch = nftStakingManager.getEpochInfo(rewardsEpoch);
    assertEq(epoch.totalStakedLicenses, 1);

    vm.warp(epoch1AfterGracePeriod);
    nftStakingManager.mintRewards(validationId, rewardsEpoch);

    // check that the delegator has rewards
    uint256 rewards = nftStakingManager.getRewardsForEpoch(delegationId, rewardsEpoch);
    assertEq(rewards, epochRewards);
    rewardsEpoch = nftStakingManager.getCurrentEpoch();

    vm.warp(epoch2InGracePeriod);
    nftStakingManager.processProof(validationId, epoch2UptimeSeconds);

    vm.warp(epoch2AfterGracePeriod);
    nftStakingManager.mintRewards(validationId, rewardsEpoch);

    rewards = nftStakingManager.getRewardsForEpoch(delegationId, rewardsEpoch);
    assertEq(rewards, epochRewards);

    vm.prank(delegator);
    (uint256 totalRewards, uint32[] memory claimedEpochNumbers) =
      nftStakingManager.claimRewards(delegationId, 2);

    assertEq(totalRewards, epochRewards * 2);
    assertEq(claimedEpochNumbers.length, 2);
    assertEq(claimedEpochNumbers[0], rewardsEpoch - 1);
    assertEq(claimedEpochNumbers[1], rewardsEpoch);
  }

  function testv2_multipleDelegatorRewards() public {
    (bytes32 validationId, address validator) = _createValidator();
    (bytes32 delegationId, address delegator) = _createDelegation(validationId, 1);
    (bytes32 delegationId2, address delegator2) = _createDelegation(validationId, 1);

    // process proof is what locks in delegator rewards
    vm.warp(block.timestamp + 1 days);
    nftStakingManager.processProof(validationId, 0);

    vm.prank(delegator);
  }

  function test_DelegationFee_NoCredits() public {
    (bytes32 validationId, address validator) = _createValidator();
    (bytes32 delegationId, address delegator) = _createDelegation(validationId, 1);

    vm.warp(block.timestamp + 1 days + 1 seconds);
    nftStakingManager.processProof(validationId, 1 days);
    vm.warp(block.timestamp + 1 hours);
    nftStakingManager.mintRewards(validationId);
    uint256 rewards = nftStakingManager.getRewardsForEpoch(delegationId, 1);
    assertEq(rewards, 900 ether);
  }

  function test_DelegationFee_AllCredits_OneLicense() public {
    (bytes32 validationId, address validator) = _createValidator();
    (bytes32 delegationId, address delegator) = _createDelegation(validationId, 1);

    vm.prank(validator);
    nftStakingManager.addPrepaidCredits(delegator, 1 days);

    vm.warp(block.timestamp + 1 days + 1 seconds);
    nftStakingManager.processProof(validationId, 1 days);
    vm.warp(block.timestamp + 1 hours);
    nftStakingManager.mintRewards(validationId);
    uint256 rewards = nftStakingManager.getRewardsForEpoch(delegationId, 1);
    assertEq(rewards, 1000 ether);
  }

  function test_DelegationFee_AllCredits_10Licenses() public {
    (bytes32 validationId, address validator) = _createValidator();
    (bytes32 delegationId, address delegator) = _createDelegation(validationId, 10);

    vm.prank(validator);
    nftStakingManager.addPrepaidCredits(delegator, 10 days);

    vm.warp(block.timestamp + 1 days + 1 seconds);
    nftStakingManager.processProof(validationId, 1 days);
    vm.warp(block.timestamp + 1 hours);
    nftStakingManager.mintRewards(validationId);
    uint256 rewards = nftStakingManager.getRewardsForEpoch(delegationId, 1);
    assertEq(rewards, 1000 ether);
  }

  function test_DelegationFee_HalfCredits_10Licenses() public {
    (bytes32 validationId, address validator) = _createValidator();
    (bytes32 delegationId, address delegator) = _createDelegation(validationId, 10);

    vm.prank(validator);
    nftStakingManager.addPrepaidCredits(delegator, 5 days);

    vm.warp(block.timestamp + 1 days + 1 seconds);
    nftStakingManager.processProof(validationId, 1 days);
    vm.warp(block.timestamp + 1 hours);
    nftStakingManager.mintRewards(validationId);
    uint256 rewards = nftStakingManager.getRewardsForEpoch(delegationId, 1);
    assertEq(rewards, 500 ether + 500 ether * 90 / 100);
  }

  function test_processProof_insufficientUptime() public {
    uint256 startTime = block.timestamp;
    uint256 epochDuration = 1 days;

    (bytes32 validationId, address validator) = _createValidator();
    (bytes32 delegationId, address delegator) = _createDelegation(validationId, 1);

    // Move to the grace period of the first epoch
    vm.warp(startTime + epochDuration + GRACE_PERIOD / 2);

    uint256 insufficientUptime = epochDuration * 70 / 100;

    vm.expectRevert(NFTStakingManager.InsufficientUptime.selector);
    nftStakingManager.processProof(validationId, insufficientUptime);
  }

  function test_processProof_missUptime() public {
    uint256 startTime = block.timestamp;
    uint256 epochDuration = 1 days;

    bytes32 validationId = _createValidator();
    (bytes32 delegationId, address delegator) = _createDelegation(validationId);

    uint256 epoch1UptimeSeconds = epochDuration * 90 / 100;
    uint256 epoch3UptimeSeconds = epoch1UptimeSeconds * 3;

    uint256 epoch1InGracePeriod = startTime + epochDuration + GRACE_PERIOD / 2;
    uint256 epoch1AfterGracePeriod = startTime + epochDuration + GRACE_PERIOD;
    uint256 epoch3InGracePeriod = startTime + epochDuration * 3 + GRACE_PERIOD / 2;
    uint256 epoch3AfterGracePeriod = startTime + epochDuration * 3 + GRACE_PERIOD;

    vm.warp(epoch1InGracePeriod);
    nftStakingManager.processProof(validationId, epoch1UptimeSeconds);

    vm.warp(epoch1AfterGracePeriod);
    nftStakingManager.mintRewards(validationId, 1);

    // skip second epoch
    vm.warp(startTime + epochDuration * 2);

    // process proof for third epoch
    vm.warp(startTime + epochDuration * 3 + GRACE_PERIOD / 2);
    nftStakingManager.processProof(validationId, epoch3UptimeSeconds);

    EpochInfo memory epoch = nftStakingManager.getEpochInfo(nftStakingManager.getCurrentEpoch() - 1);
    console2.log("epoch.totalStakedLicenses", epoch.totalStakedLicenses);
    console2.log("current epoch", nftStakingManager.getCurrentEpoch());
    assertEq(epoch.totalStakedLicenses, 1);

    vm.warp(epoch3AfterGracePeriod);
    nftStakingManager.mintRewards(validationId, 3);
    uint256 rewards = nftStakingManager.getRewardsForEpoch(delegationId, 3);
    assertEq(rewards, epochRewards);
  }

  function _createValidator() internal returns (bytes32) {
    address validator = getActor("Validator");
    uint256 hardwareTokenId = hardwareNft.mint(validator);

    vm.startPrank(admin);
    nftStakingManager.grantRole(nftStakingManager.PREPAYMENT_ROLE(), validator);
    vm.stopPrank();

    vm.startPrank(validator);
    bytes32 validationId = nftStakingManager.initiateValidatorRegistration(
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

    return (validationId, validator);
  }

  function _createDelegation(bytes32 validationId, uint256 licenseCount)
    internal
    returns (bytes32, address)
  {
    address delegator = getActor("Delegator1");
    uint256[] memory tokenIds = new uint256[](licenseCount);

    for (uint256 i = 0; i < licenseCount; i++) {
      tokenIds[i] = nft.mint(delegator);
    }

    vm.startPrank(delegator);
    bytes32 delegationId = nftStakingManager.initiateDelegatorRegistration(validationId, tokenIds);
    nftStakingManager.completeDelegatorRegistration(delegationId, 0);
    vm.stopPrank();

    return (delegationId, delegator);
  }

  function test_multipleDelegatorsWithDifferentTokens() public {
    uint256 startTime = block.timestamp;
    uint256 epochDuration = 1 days;
    uint256 epochInGracePeriod = startTime + epochDuration + GRACE_PERIOD / 2;
    uint256 epochAfterGracePeriod = startTime + epochDuration + GRACE_PERIOD;

    // Create validator
    bytes32 validationId = _createValidator();

    // Create delegators with different token amounts
    address delegator1 = getActor("Delegator1");
    address delegator2 = getActor("Delegator2");
    address delegator3 = getActor("Delegator3");

    // Mint different amounts of tokens to each delegator
    uint256[] memory tokenIds1 = nft.batchMint(delegator1, 1); // 1 token
    uint256[] memory tokenIds2 = nft.batchMint(delegator2, 2); // 2 tokens
    uint256[] memory tokenIds3 = nft.batchMint(delegator3, 3); // 3 tokens

    // Record prepayments for all tokens
    vm.startPrank(admin);
    nftStakingManager.recordPrepayment(1, uint40(block.timestamp + 1 days));
    nftStakingManager.recordPrepayment(2, uint40(block.timestamp + 1 days));
    nftStakingManager.recordPrepayment(3, uint40(block.timestamp + 1 days));
    nftStakingManager.recordPrepayment(4, uint40(block.timestamp + 1 days));
    nftStakingManager.recordPrepayment(5, uint40(block.timestamp + 1 days));
    nftStakingManager.recordPrepayment(6, uint40(block.timestamp + 1 days));
    vm.stopPrank();

    // Create delegations with different token amounts
    vm.startPrank(delegator1);
    bytes32 delegationId1 = nftStakingManager.initiateDelegatorRegistration(validationId, tokenIds1);
    nftStakingManager.completeDelegatorRegistration(delegationId1, 0);
    vm.stopPrank();

    vm.startPrank(delegator2);
    bytes32 delegationId2 = nftStakingManager.initiateDelegatorRegistration(validationId, tokenIds2);
    nftStakingManager.completeDelegatorRegistration(delegationId2, 0);
    vm.stopPrank();

    vm.startPrank(delegator3);
    bytes32 delegationId3 = nftStakingManager.initiateDelegatorRegistration(validationId, tokenIds3);
    nftStakingManager.completeDelegatorRegistration(delegationId3, 0);
    vm.stopPrank();

    // Verify total staked licenses
    assertEq(nftStakingManager.getCurrentTotalStakedLicenses(), 6);

    // Process proof for the epoch
    vm.warp(epochInGracePeriod);
    uint256 uptimeSeconds = epochDuration * 90 / 100;
    nftStakingManager.processProof(validationId, uptimeSeconds);

    // Mint rewards after grace period
    vm.warp(epochAfterGracePeriod);
    uint32 currentEpoch = nftStakingManager.getCurrentEpoch() - 1;
    nftStakingManager.mintRewards(validationId, currentEpoch);

    // Calculate expected rewards per token
    uint256 rewardsPerToken = epochRewards / 6; // Total rewards divided by total tokens
    console2.log("rewardsPerToken", rewardsPerToken);
    console2.log("rewardsperlicen", nftStakingManager.calculateRewardsPerLicense(currentEpoch));

    // Verify each delegator's rewards
    uint256 rewards1 = nftStakingManager.getRewardsForEpoch(delegationId1, currentEpoch);
    assertEq(rewards1, rewardsPerToken * 1); // 1 token worth of rewards

    uint256 rewards2 = nftStakingManager.getRewardsForEpoch(delegationId2, currentEpoch);
    assertEq(rewards2, rewardsPerToken * 2); // 2 tokens worth of rewards

    uint256 rewards3 = nftStakingManager.getRewardsForEpoch(delegationId3, currentEpoch);
    assertEq(rewards3, rewardsPerToken * 3); // 3 tokens worth of rewards

    // Verify total rewards match epoch rewards
    assertApproxEqAbs(rewards1 + rewards2 + rewards3, epochRewards, 4);
  }
}
