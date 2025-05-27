// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

import { Base } from "./Base.sol";

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
} from "../../contracts/NFTStakingManager.sol";

import { NodeLicense, NodeLicenseSettings } from "../../contracts/tokens/NodeLicense.sol";

import {
  PChainOwner,
  Validator,
  ValidatorStatus
} from "icm-contracts-2.0.0/contracts/validator-manager/interfaces/IACP99Manager.sol";

import { ERC721Mock } from "../mocks/ERC721Mock.sol";
import { NativeMinterMock } from "../mocks/NativeMinterMock.sol";
import { MockValidatorManager } from "../mocks/ValidatorManagerMock.sol";

import { IWarpMessenger, WarpMessage } from "./IWarpMessenger.sol";

import { ERC1967Proxy } from "@openzeppelin-contracts-5.3.0/proxy/ERC1967/ERC1967Proxy.sol";
import { console2 } from "forge-std-1.9.6/src/console2.sol";
import { PChainOwner } from "icm-contracts-2.0.0/contracts/validator-manager/ACP99Manager.sol";

import { ValidatorMessages } from
  "icm-contracts-2.0.0/contracts/validator-manager/ValidatorMessages.sol";

abstract contract NFTStakingManagerBase is Base {
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

  function setUp() public virtual override {
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
