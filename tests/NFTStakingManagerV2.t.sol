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

import { ERC1967Proxy } from "@openzeppelin-contracts-5.2.0/proxy/ERC1967/ERC1967Proxy.sol";
import { console2 } from "forge-std-1.9.6/src/console2.sol";
import { PChainOwner } from "icm-contracts-8817f47/contracts/validator-manager/ACP99Manager.sol";

contract NFTStakingManagerTest is Base {
  ERC721Mock public nft;
  ERC721Mock public hardwareNft;
  MockValidatorManager public validatorManager;
  NFTStakingManager public nftStakingManager;

  address public admin;
  address public deployer;

  uint256 public epochRewards = 1000 ether;
  uint16 public MAX_LICENSES_PER_VALIDATOR = 10;
  uint64 public LICENSE_WEIGHT = 1000;
  uint64 public HARDWARE_LICENSE_WEIGHT = 0;
  uint32 public GRACE_PERIOD = 1 hours;

  function setUp() public override {
    super.setUp();
    admin = getActor("Admin");
    deployer = getActor("Deployer");

    address[] memory addresses = new address[](1);
    addresses[0] = 0x1234567812345678123456781234567812345678;
    DEFAULT_P_CHAIN_OWNER = PChainOwner({ threshold: 1, addresses: addresses });

    vm.startPrank(deployer);

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

    nftStakingManager.grantRole(nftStakingManager.PREPAYMENT_ROLE(), admin);

    NativeMinterMock nativeMinter = new NativeMinterMock();
    vm.etch(0x0200000000000000000000000000000000000001, address(nativeMinter).code);
    vm.stopPrank();
  }

  function _defaultNFTStakingManagerSettings(
    address validatorManager_,
    address license_,
    address hardwareLicense_
  ) internal view returns (NFTStakingManagerSettings memory) {
    return NFTStakingManagerSettings({
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
    hardwareNft.mint(validator, 1);

    uint256 hardwareTokenId = 1;

    vm.startPrank(validator);
    bytes32 validationId = nftStakingManager.initiateValidatorRegistration(
      DEFAULT_NODE_ID,
      DEFAULT_BLS_PUBLIC_KEY,
      DEFAULT_BLS_POP,
      DEFAULT_P_CHAIN_OWNER,
      DEFAULT_P_CHAIN_OWNER,
      hardwareTokenId
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
    bytes32 validationId = _createValidator();

    address delegator = getActor("Delegator");
    nft.mint(delegator, 1);
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = 1;

    // we need to prepay for these too
    vm.prank(admin);
    nftStakingManager.recordPrepayment(1, uint40(block.timestamp + 1 days));

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

  function test_processProof() public {
    uint256 startTime = block.timestamp;
    uint256 epochDuration = 1 days;

    uint256 epoch1InGracePeriod = startTime + epochDuration + GRACE_PERIOD / 2;
    uint256 epoch1AfterGracePeriod = startTime + epochDuration + GRACE_PERIOD;

    uint256 epoch2InGracePeriod = startTime + epochDuration * 2 + GRACE_PERIOD - 1;
    uint256 epoch2AfterGracePeriod = startTime + epochDuration * 2 + GRACE_PERIOD;

    uint256 epoch1UptimeSeconds = startTime + epochDuration * 90 / 100;
    uint256 epoch2UptimeSeconds = epoch1UptimeSeconds + epochDuration * 90 / 100;

    uint32 rewardsEpoch = nftStakingManager.getCurrentEpoch();
    bytes32 validationId = _createValidator();
    (bytes32 delegationId, address delegator) = _createDelegation(validationId);

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

  function test_processProof_insufficientUptime() public {
    uint256 startTime = block.timestamp;
    uint256 epochDuration = 1 days;

    bytes32 validationId = _createValidator();
    (bytes32 delegationId, address delegator) = _createDelegation(validationId);

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

    uint256 epoch1UptimeSeconds = startTime + epochDuration * 90 / 100;

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
    hardwareNft.mint(validator, 1);

    uint256 hardwareTokenId = 1;

    vm.startPrank(validator);
    bytes32 validationId = nftStakingManager.initiateValidatorRegistration(
      DEFAULT_NODE_ID,
      DEFAULT_BLS_PUBLIC_KEY,
      DEFAULT_BLS_POP,
      DEFAULT_P_CHAIN_OWNER,
      DEFAULT_P_CHAIN_OWNER,
      hardwareTokenId
    );
    nftStakingManager.completeValidatorRegistration(0);
    vm.stopPrank();

    return validationId;
  }

  function _createDelegation(bytes32 validationId) internal returns (bytes32, address) {
    address delegator = getActor(string(abi.encodePacked(validationId)));
    nft.mint(delegator, 1);
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = 1;

    vm.startPrank(delegator);
    bytes32 delegationId = nftStakingManager.initiateDelegatorRegistration(validationId, tokenIds);
    nftStakingManager.completeDelegatorRegistration(delegationId, 0);
    vm.stopPrank();

    return (delegationId, delegator);
  }
}
