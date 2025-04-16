// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { console2 } from "forge-std-1.9.6/src/console2.sol";

import { IERC721 } from "@openzeppelin-contracts-5.2.0/token/ERC721/IERC721.sol";
import { Address } from "@openzeppelin-contracts-5.2.0/utils/Address.sol";

import { EnumerableSet } from "@openzeppelin-contracts-5.2.0/utils/structs/EnumerableSet.sol";
import { AccessControlUpgradeable } from
  "@openzeppelin-contracts-upgradeable-5.2.0/access/AccessControlUpgradeable.sol";
import { Initializable } from
  "@openzeppelin-contracts-upgradeable-5.2.0/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from
  "@openzeppelin-contracts-upgradeable-5.2.0/proxy/utils/UUPSUpgradeable.sol";
import {
  PChainOwner,
  Validator,
  ValidatorStatus
} from "icm-contracts-8817f47/contracts/validator-manager/ACP99Manager.sol";
import { ValidatorManager } from
  "icm-contracts-8817f47/contracts/validator-manager/ValidatorManager.sol";
import { ValidatorMessages } from
  "icm-contracts-8817f47/contracts/validator-manager/ValidatorMessages.sol";

interface INativeMinter {
  function mintNativeCoin(address addr, uint256 amount) external;
}

struct EpochInfo {
  uint256 totalStakedLicenses;
}

struct NodeInfo {
  address owner;
  bytes blsPublicKey;
  bytes blsPoP;
}

struct ValidationInfo {
  address owner;
  uint256 hardwareTokenId;
  uint32 startEpoch;
  uint32 endEpoch;
  uint32 licenseCount;
  bytes registrationMessage;
  EnumerableSet.Bytes32Set delegationIds;
}

struct ValidationInfoView {
  address owner;
  uint256 hardwareTokenId;
  uint32 startEpoch;
  uint32 endEpoch;
  uint32 licenseCount;
  bytes registrationMessage;
}

struct DelegationInfo {
  address owner;
  bytes32 validationId;
  uint32 startEpoch;
  uint32 endEpoch;
  uint256[] tokenIds;
  mapping(uint32 epochNumber => uint256 rewards) claimableRewardsPerEpoch; // will get set to zero when claimed
  mapping(uint32 epochNumber => bool passedUptime) uptimeCheck; // will get set to zero when claimed
  EnumerableSet.UintSet claimableEpochNumbers;
}

// Without nested mappings, for view functions
struct DelegationInfoView {
  address owner;
  bytes32 validationId;
  uint32 startEpoch;
  uint32 endEpoch;
  uint256[] tokenIds;
}

struct NFTStakingManagerSettings {
  address validatorManager;
  address license;
  address hardwareLicense;
  uint32 initialEpochTimestamp;
  uint32 epochDuration;
  uint64 licenseWeight;
  uint64 hardwareLicenseWeight;
  uint256 epochRewards;
  uint16 maxLicensesPerValidator;
  bool requireHardwareTokenId;
  uint32 gracePeriod;
}

contract NFTStakingManager is Initializable, AccessControlUpgradeable, UUPSUpgradeable {
  using Address for address payable;
  using EnumerableSet for EnumerableSet.UintSet;
  using EnumerableSet for EnumerableSet.Bytes32Set;

  error TokenAlreadyLocked(uint256 tokenId);
  error UnauthorizedOwner(address owner);
  error EpochOutOfRange(uint32 currentEpoch, uint32 startEpoch, uint32 endEpoch);

  event TokensLocked(address indexed owner, bytes32 indexed stakeId, uint256[] tokenIds);
  event TokensUnlocked(address indexed owner, bytes32 indexed stakeId, uint256[] tokenIds);
  event RewardsMinted(uint32 indexed epochNumber, bytes32 indexed stakeId, uint256 rewards);
  event RewardsClaimed(uint32 indexed epochNumber, bytes32 indexed stakeId, uint256 rewards);

  // keccak256(abi.encode(uint256(keccak256("gogopool.storage.NFTStakingManagerStorage")) - 1)) & ~bytes32(uint256(0xff));
  bytes32 public constant NFT_STAKING_MANAGER_STORAGE_LOCATION =
    0xb2bea876b5813e5069ed55d22ad257d01245c883a221b987791b00df2f4dfa00;

  bytes32 public constant PREPAYMENT_ROLE = keccak256("PREPAYMENT_ROLE");

  struct NFTStakingManagerStorage {
    ValidatorManager manager;
    IERC721 licenseContract;
    IERC721 hardwareLicenseContract;
    uint16 maxLicensesPerValidator; // 100
    uint32 initialEpochTimestamp; // 1716864000 2024-05-27 00:00:00 UTC
    uint32 currentTotalStakedLicenses;
    uint32 epochDuration; // 1 days
    uint64 licenseWeight; // 1000
    uint64 hardwareLicenseWeight; // 1 million
    uint256 epochRewards; // 1_369_863 (2_500_000_000 / (365 * 5)) * 1 ether
    uint32 gracePeriod; // starting at 1 hours
    EnumerableSet.Bytes32Set validationIds;
    // We dont xfer nft to this contract, we just mark it as locked
    mapping(uint256 tokenId => bytes32 delegationId) tokenLockedBy;
    mapping(uint256 tokenId => bytes32 validationId) hardwareTokenLockedBy;
    mapping(uint32 epochNumber => EpochInfo) epochs;
    // Ensure that we only ever mint rewards once for a given epochNumber/tokenId combo
    mapping(uint32 epochNumber => mapping(uint256 tokenId => bool isRewardsMinted)) isRewardsMinted;
    // Track prepayments for tokenIds
    mapping(uint256 tokenId => uint40 endTimestamp) prepayments;
    mapping(bytes32 validationId => ValidationInfo) validations;
    mapping(bytes32 delegationId => DelegationInfo) delegations;
    mapping(bytes20 nodeID => NodeInfo) nodes;
  }

  NFTStakingManagerStorage private _storage;

  constructor() {
    _disableInitializers();
  }

  function initialize(NFTStakingManagerSettings memory settings) public initializer {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();

    _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);

    $.manager = ValidatorManager(settings.validatorManager);
    $.licenseContract = IERC721(settings.license);
    $.hardwareLicenseContract = IERC721(settings.hardwareLicense);
    $.initialEpochTimestamp = settings.initialEpochTimestamp;
    $.epochDuration = settings.epochDuration;
    $.licenseWeight = settings.licenseWeight;
    $.hardwareLicenseWeight = settings.hardwareLicenseWeight;
    $.epochRewards = settings.epochRewards;
    $.gracePeriod = settings.gracePeriod;
    $.maxLicensesPerValidator = settings.maxLicensesPerValidator;
  }

  function initiateDelegatorRegistration(bytes32 validationId, uint256[] calldata tokenIds)
    public
    returns (bytes32)
  {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    for (uint256 i = 0; i < tokenIds.length; i++) {
      // TODO do we need a min duration in general? if so account for it here.
      // If prepayment is zero then we deduct delegation fees on rewards minting
      if ($.prepayments[tokenIds[i]] > 0 && $.prepayments[tokenIds[i]] < block.timestamp) {
        revert("Prepayment for tokenId X has expired");
      }
    }

    ValidationInfo storage validation = $.validations[validationId];
    if (validation.startEpoch == 0) {
      revert("Validator registration not complete");
    }

    if (validation.licenseCount + tokenIds.length > $.maxLicensesPerValidator) {
      revert("Max licenses per validator reached");
    }

    Validator memory validator = $.manager.getValidator(validationId);
    uint64 newWeight = validator.weight + _getWeight(tokenIds.length);
    (uint64 nonce,) = $.manager.initiateValidatorWeightUpdate(validationId, newWeight);

    bytes32 delegationId = keccak256(abi.encodePacked(validationId, nonce));

    validation.delegationIds.add(delegationId);

    _lockTokens(delegationId, tokenIds);

    DelegationInfo storage newDelegation = $.delegations[delegationId];
    newDelegation.owner = msg.sender;
    newDelegation.tokenIds = tokenIds;
    newDelegation.validationId = validationId;

    return delegationId;
  }

  function completeDelegatorRegistration(bytes32 delegationId, uint32 messageIndex) public {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    (bytes32 validationId,) = $.manager.completeValidatorWeightUpdate(messageIndex);
    DelegationInfo storage delegation = $.delegations[delegationId];
    if (validationId != delegation.validationId) {
      revert("Validation ID mismatch");
    }
    ValidationInfo storage validation = $.validations[validationId];
    validation.licenseCount += uint32(delegation.tokenIds.length);

    delegation.startEpoch = getCurrentEpoch();
  }

  // TODO enforce a min duration?
  function initiateDelegatorRemoval(bytes32 delegationId) external {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();

    DelegationInfo storage delegation = $.delegations[delegationId];
    ValidationInfo storage validation = $.validations[delegation.validationId];
    Validator memory validator = $.manager.getValidator(delegation.validationId);

    if (delegation.owner != msg.sender) revert UnauthorizedOwner(msg.sender);

    // TODO figure out which vars to update now and which after the weight update

    delegation.endEpoch = getCurrentEpoch();
    validation.licenseCount -= uint32(delegation.tokenIds.length);
    uint64 newWeight = validator.weight - _getWeight(delegation.tokenIds.length);
    validation.delegationIds.remove(delegationId);

    (uint64 nonce,) = $.manager.initiateValidatorWeightUpdate(delegation.validationId, newWeight);
    // do we need to store nonce?
  }

  function completeDelegatorRemoval(bytes32 delegationId, uint32 messageIndex)
    external
    returns (bytes32)
  {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();

    // Complete the weight update
    // TODO I think this allows anyone to use the "wrong" delegationId? Maybe need a "pending" state
    // we set before, then check it here?
    (bytes32 validationId,) = $.manager.completeValidatorWeightUpdate(messageIndex);
    if (validationId != $.delegations[delegationId].validationId) {
      revert("Validation ID mismatch");
    }

    _unlockTokens(delegationId, $.delegations[delegationId].tokenIds);

    return delegationId;
  }

  function initiateValidatorRegistration(
    bytes memory nodeID,
    bytes memory blsPublicKey,
    bytes memory blsPoP,
    PChainOwner memory remainingBalanceOwner,
    PChainOwner memory disableOwner,
    uint256 hardwareTokenId
  ) public returns (bytes32) {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    uint64 registrationExpiry = uint64(block.timestamp + 1 days);
    uint64 weight = $.hardwareLicenseWeight;
    bytes32 validationId = $.manager.initiateValidatorRegistration(
      nodeID, blsPublicKey, registrationExpiry, remainingBalanceOwner, disableOwner, weight
    );

    _lockHardwareToken(validationId, hardwareTokenId);

    $.validationIds.add(validationId);

    // The bytes of this message are required to end the validation period, and ValidatorManager
    // does not expose it or keep it around, so we store it here.
    (, bytes memory registerL1ValidatorMessage) = ValidatorMessages.packRegisterL1ValidatorMessage(
      ValidatorMessages.ValidationPeriod({
        subnetID: $.manager.subnetID(),
        nodeID: nodeID,
        blsPublicKey: blsPublicKey,
        remainingBalanceOwner: remainingBalanceOwner,
        disableOwner: disableOwner,
        registrationExpiry: registrationExpiry,
        weight: weight
      })
    );

    ValidationInfo storage validation = $.validations[validationId];
    validation.owner = msg.sender;
    validation.hardwareTokenId = hardwareTokenId;
    validation.registrationMessage = registerL1ValidatorMessage;

    // The blsPoP is required to complete the validator registration on the P-Chain, so store it here
    // for an off-chain service to use to complete the registration.
    bytes20 fixedNodeID = _fixedNodeID(nodeID);
    $.nodes[fixedNodeID] =
      NodeInfo({ owner: msg.sender, blsPublicKey: blsPublicKey, blsPoP: blsPoP });

    return validationId;
  }

  function completeValidatorRegistration(uint32 messageIndex) external returns (bytes32) {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    bytes32 validationId = $.manager.completeValidatorRegistration(messageIndex);

    ValidationInfo storage validation = $.validations[validationId];
    validation.startEpoch = getCurrentEpoch();
    return validationId;
  }

  function initiateValidatorRemoval(bytes32 validationId) external {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    ValidationInfo storage validation = $.validations[validationId];
    if (validation.owner != msg.sender) revert UnauthorizedOwner(msg.sender);
    validation.endEpoch = getCurrentEpoch();
    $.manager.initiateValidatorRemoval(validationId);
    // TODO: remove delegators
  }

  function completeValidatorRemoval(bytes32 validationId, uint32 messageIndex)
    external
    returns (bytes32)
  {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    ValidationInfo storage validation = $.validations[validationId];

    $.manager.completeValidatorRemoval(messageIndex);

    _unlockHardwareToken(validation.hardwareTokenId);

    for (uint256 i = 0; i < validation.delegationIds.length(); i++) {
      bytes32 delegationId = validation.delegationIds.at(i);
      _unlockTokens(delegationId, $.delegations[delegationId].tokenIds);
    }
    // Should we delete? Or leave in for historical querying with view funcs?
    delete $.validations[validationId];
    $.validationIds.remove(validationId);
    return validationId;
  }

  function recordPrepayment(uint256 tokenId, uint40 endTimestamp)
    external
    onlyRole(PREPAYMENT_ROLE)
  {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    // Check if end timestamp is in the future
    if (endTimestamp <= block.timestamp) {
      revert("End timestamp must be in the future");
    }

    // Record the prepayment
    $.prepayments[tokenId] = endTimestamp;
  }

  // Anyone can call mintRewards functions to mint rewards (prob backend cron process)
  // No special permissions necessary. In future this could accept uptime proof as well.
  // after verifiying the total amount
  function mintRewards(bytes32[] calldata validationIds) external {
    for (uint256 i = 0; i < validationIds.length; i++) {
      mintRewards(validationIds[i]);
    }
  }

  function processProof(bytes32 validationId, uint256) public {
    // for now i'm just going to say that the uptime proof is good no matter what
    // (bytes32 validationID, uint64 uptime) = ValidatorMessages.unpackValidationUptimeMessage(
    //   _getPChainWarpMessage(messageIndex, uptimeBlockchainID).payload
    // );

    // this has to be called within a grace period window
    uint32 epoch = getCurrentEpoch();
    epoch--;
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();

    console2.log("epoch", epoch);
    console2.log("grace period", $.gracePeriod);
    console2.log("has grace period passed", _hasGracePeriodPassed(epoch));
    if (_hasGracePeriodPassed(epoch)) {
      revert("Grace period has passed");
    }

    uint32 expectedUptime = getExpectedUptime(validationId, epoch);
    console2.log("expected uptime", expectedUptime);
    // TODO: actually check the uptime
    if (false) {
      revert("uptime not passed for validation");
    }

    // then if it passes, record total validators for the epoch
    // and say that the tokenIds passed uptime

    EpochInfo storage epochInfo = $.epochs[epoch];

    ValidationInfo storage validation = $.validations[validationId];
    uint256 totalDelegations = validation.delegationIds.length();

    // then for each delegation that was on the active validator, record that they can get rewards
    for (uint256 i = 0; i < totalDelegations; i++) {
      bytes32 delegationId = validation.delegationIds.at(i);
      DelegationInfo storage delegation = $.delegations[delegationId];
      delegation.uptimeCheck[epoch] = true;
      epochInfo.totalStakedLicenses += delegation.tokenIds.length;
    }
  }

  function mintRewards(bytes32 validationId) public {
    uint32 epoch = getCurrentEpoch();
    epoch--;
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    ValidationInfo storage validation = $.validations[validationId];

    if (!_hasGracePeriodPassed(epoch)) {
      revert("Grace period has not passed");
    }

    uint256 totalDelegations = validation.delegationIds.length();

    for (uint256 i = 0; i < totalDelegations; i++) {
      bytes32 delegationId = validation.delegationIds.at(i);
      DelegationInfo storage delegation = $.delegations[delegationId];
      if (delegation.uptimeCheck[epoch]) {
        mintDelegatorRewards(epoch, delegationId);
      }
    }
  }

  // verify that the user had a valid uptime for the given epcoh
  function mintDelegatorRewards(uint32 epoch, bytes32 delegationId) public {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    DelegationInfo storage delegation = $.delegations[delegationId];

    if (delegation.owner == address(0)) {
      revert("Stake does not exist");
    }

    if (epoch < delegation.startEpoch || (epoch > delegation.endEpoch && delegation.endEpoch != 0))
    {
      revert EpochOutOfRange(epoch, delegation.startEpoch, delegation.endEpoch);
    }

    for (uint256 i = 0; i < delegation.tokenIds.length; i++) {
      // TODO if either of these happen it seems unrecoverable? How would we fix?
      // admin fn to manually add data to rewards and locked mappings?
      if ($.tokenLockedBy[delegation.tokenIds[i]] != delegationId) {
        revert("Token not locked by this stakeId");
      }
      if ($.isRewardsMinted[epoch][delegation.tokenIds[i]]) {
        revert("Rewards already minted for this tokenId");
      }

      $.isRewardsMinted[epoch][delegation.tokenIds[i]] = true;
    }

    uint256 rewards = calculateRewardsPerLicense(epoch) * delegation.tokenIds.length;
    delegation.claimableRewardsPerEpoch[epoch] = rewards;
    delegation.claimableEpochNumbers.add(uint256(epoch));
    INativeMinter(0x0200000000000000000000000000000000000001).mintNativeCoin(address(this), rewards);
    emit RewardsMinted(epoch, delegationId, rewards);
  }

  function claimRewards(address owner) external { }

  function claimRewards(bytes32 delegationId, uint32 maxEpochs)
    external
    returns (uint256, uint32[] memory)
  {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    DelegationInfo storage delegation = $.delegations[delegationId];

    console2.log("delegation.owner", delegation.owner);
    if (delegation.owner != msg.sender) revert UnauthorizedOwner(msg.sender);
    if (maxEpochs > delegation.claimableEpochNumbers.length()) {
      maxEpochs = uint32(delegation.claimableEpochNumbers.length());
    }

    uint256 totalRewards = 0;
    uint32[] memory claimedEpochNumbers = new uint32[](maxEpochs);

    for (uint32 i = 0; i < maxEpochs; i++) {
      uint32 epochNumber = uint32(delegation.claimableEpochNumbers.at(i));
      uint256 rewards = delegation.claimableRewardsPerEpoch[epochNumber];

      // State changes
      claimedEpochNumbers[i] = epochNumber;
      totalRewards += rewards;
      delegation.claimableEpochNumbers.remove(uint256(epochNumber));
      delegation.claimableRewardsPerEpoch[epochNumber] = 0;
    }

    // Events (after all state changes)
    for (uint32 i = 0; i < maxEpochs; i++) {
      emit RewardsClaimed(
        claimedEpochNumbers[i],
        delegationId,
        delegation.claimableRewardsPerEpoch[claimedEpochNumbers[i]]
      );
    }

    payable(delegation.owner).sendValue(totalRewards);
    return (totalRewards, claimedEpochNumbers);
  }

  function calculateRewardsPerLicense(uint32 epochNumber) public view returns (uint256) {
    // maybe only allow checking for currentEpoch-1 or earlier?
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    return $.epochRewards / $.epochs[epochNumber].totalStakedLicenses;
  }

  function getEpochByTimestamp(uint32 timestamp) public view returns (uint32) {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    // we don't want to have a 0 epoch, because 0 is also a falsy value
    uint32 epoch = (timestamp - $.initialEpochTimestamp) / $.epochDuration;
    return epoch + 1;
  }

  function getCurrentEpoch() public view returns (uint32) {
    return getEpochByTimestamp(uint32(block.timestamp));
  }

  function getEpochEndTime(uint32 epoch) public view returns (uint40) {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    return $.initialEpochTimestamp + (epoch) * $.epochDuration;
  }

  function getExpectedUptime(bytes32 validationId, uint32 epoch) public view returns (uint32) {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();

    // Get the validator's start epoch from the validation info
    ValidationInfo storage validation = $.validations[validationId];
    if (validation.startEpoch == 0) {
      revert("Validator not registered");
    }

    // Calculate number of epochs since validator started
    console2.log("epoch", epoch);
    console2.log("validation start epoch", validation.startEpoch);
    if (epoch < validation.startEpoch) {
      revert("Epoch is before validator started");
    }

    uint32 epochsActive = epoch - validation.startEpoch;
    if (epochsActive == 0) {
      // If validator just started this epoch, expect 80% of current epoch
      return $.epochDuration * 80 / 100;
    }

    // Calculate total time active in seconds
    uint32 totalTimeActive = epochsActive * $.epochDuration;

    // Return 80% of total time active
    return totalTimeActive * 80 / 100;
  }

  function getCurrentTotalStakedLicenses() external view returns (uint32) {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    uint32 totalStakedLicenses = 0;
    for (uint256 i = 0; i < $.validationIds.length(); i++) {
      bytes32 validationId = $.validationIds.at(i);
      for (uint256 j = 0; j < $.validations[validationId].delegationIds.length(); j++) {
        bytes32 delegationId = $.validations[validationId].delegationIds.at(j);
        totalStakedLicenses += uint32($.delegations[delegationId].tokenIds.length);
      }
    }
    return totalStakedLicenses;
  }

  function getTokenLockedBy(uint256 tokenId) external view returns (bytes32) {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    return $.tokenLockedBy[tokenId];
  }

  function getValidationIds() external view returns (bytes32[] memory) {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    return $.validationIds.values();
  }

  function getDelegationInfoView(bytes32 delegationId)
    external
    view
    returns (DelegationInfoView memory)
  {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    DelegationInfo storage delegation = $.delegations[delegationId];
    return DelegationInfoView({
      owner: delegation.owner,
      validationId: delegation.validationId,
      startEpoch: delegation.startEpoch,
      endEpoch: delegation.endEpoch,
      tokenIds: delegation.tokenIds
    });
  }

  function getValidationInfoView(bytes32 validationId)
    external
    view
    returns (ValidationInfoView memory)
  {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    ValidationInfo storage validation = $.validations[validationId];
    return ValidationInfoView({
      owner: validation.owner,
      hardwareTokenId: validation.hardwareTokenId,
      startEpoch: validation.startEpoch,
      endEpoch: validation.endEpoch,
      licenseCount: validation.licenseCount,
      registrationMessage: validation.registrationMessage
    });
  }

  function getNodeInfo(bytes20 nodeID) external view returns (NodeInfo memory) {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    return $.nodes[nodeID];
  }

  function getRewardsForEpoch(bytes32 delegationId, uint32 epoch) external view returns (uint256) {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    return $.delegations[delegationId].claimableRewardsPerEpoch[epoch];
  }

  function _getNFTStakingManagerStorage() private pure returns (NFTStakingManagerStorage storage $) {
    // solhint-disable-next-line no-inline-assembly
    assembly {
      $.slot := NFT_STAKING_MANAGER_STORAGE_LOCATION
    }
  }

  function _lockTokens(bytes32 stakeId, uint256[] memory tokenIds) internal {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    address owner;
    for (uint256 i = 0; i < tokenIds.length; i++) {
      uint256 tokenId = tokenIds[i];
      owner = $.licenseContract.ownerOf(tokenId);
      if (owner != msg.sender) revert UnauthorizedOwner(owner);
      if ($.tokenLockedBy[tokenId] != bytes32(0)) revert TokenAlreadyLocked(tokenId);
      $.tokenLockedBy[tokenId] = stakeId;
    }
    emit TokensLocked(owner, stakeId, tokenIds);
  }

  function _lockHardwareToken(bytes32 stakeId, uint256 tokenId) internal {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    address owner = $.hardwareLicenseContract.ownerOf(tokenId);
    if (owner != msg.sender) revert UnauthorizedOwner(owner);
    if ($.hardwareTokenLockedBy[tokenId] != bytes32(0)) revert TokenAlreadyLocked(tokenId);
    $.hardwareTokenLockedBy[tokenId] = stakeId;
  }

  function _unlockTokens(bytes32 stakeId, uint256[] memory tokenIds) internal {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    DelegationInfo storage stake = $.delegations[stakeId];
    address owner = stake.owner;
    for (uint256 i = 0; i < tokenIds.length; i++) {
      $.tokenLockedBy[tokenIds[i]] = bytes32(0);
    }
    emit TokensUnlocked(owner, stakeId, tokenIds);
  }

  function _unlockHardwareToken(uint256 tokenId) internal {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    $.hardwareTokenLockedBy[tokenId] = bytes32(0);
  }

  function _getWeight(uint256 tokenCount) internal view returns (uint64) {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    return uint64(tokenCount * $.licenseWeight);
  }

  function _hasGracePeriodPassed(uint32 epoch) internal view returns (bool) {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    return block.timestamp >= getEpochEndTime(epoch) + $.gracePeriod;
  }

  /**
   * @notice Converts a nodeID to a fixed length of 20 bytes.
   * @param nodeID The nodeID to convert.
   * @return The fixed length nodeID.
   */
  function _fixedNodeID(bytes memory nodeID) private pure returns (bytes20) {
    bytes20 fixedID;
    // solhint-disable-next-line no-inline-assembly
    assembly {
      fixedID := mload(add(nodeID, 32))
    }
    return fixedID;
  }

  function _authorizeUpgrade(address newImplementation)
    internal
    override
    onlyRole(DEFAULT_ADMIN_ROLE)
  { }
}
