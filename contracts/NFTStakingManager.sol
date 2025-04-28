// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { console2 } from "forge-std-1.9.6/src/console2.sol";

import { IERC721 } from "@openzeppelin-contracts-5.3.0/token/ERC721/IERC721.sol";
import { Address } from "@openzeppelin-contracts-5.3.0/utils/Address.sol";

import { EnumerableMap } from "@openzeppelin-contracts-5.3.0/utils/structs/EnumerableMap.sol";
import { EnumerableSet } from "@openzeppelin-contracts-5.3.0/utils/structs/EnumerableSet.sol";

import { AccessControlUpgradeable } from
  "@openzeppelin-contracts-upgradeable-5.3.0/access/AccessControlUpgradeable.sol";
import { Initializable } from
  "@openzeppelin-contracts-upgradeable-5.3.0/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from
  "@openzeppelin-contracts-upgradeable-5.3.0/proxy/utils/UUPSUpgradeable.sol";
import { ContextUpgradeable } from
  "@openzeppelin-contracts-upgradeable-5.3.0/utils/ContextUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from
  "@openzeppelin-contracts-upgradeable-5.3.0/utils/ReentrancyGuardUpgradeable.sol";

import {
  PChainOwner,
  Validator,
  ValidatorStatus
} from "icm-contracts-d426c55/contracts/validator-manager/ACP99Manager.sol";
import { ValidatorManager } from
  "icm-contracts-d426c55/contracts/validator-manager/ValidatorManager.sol";
import { ValidatorMessages } from
  "icm-contracts-d426c55/contracts/validator-manager/ValidatorMessages.sol";

import { IWarpMessenger, WarpMessage } from "./subnet-evm/IWarpMessenger.sol";

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
  uint32 startEpoch; // 4 bytes
  uint32 endEpoch; // 4 bytes
  uint32 licenseCount; // 4 bytes
  uint32 lastUptimeSeconds; // 4 bytes
  uint32 lastSubmissionTime; // 4 bytes
  uint32 delegationFeeBips; // 4 bytes
  address owner; // 20 bytes
  uint256 hardwareTokenId; // 32 bytes
  bytes registrationMessage; // 32 bytes
  EnumerableSet.Bytes32Set delegationIds;
  mapping(uint32 epochNumber => uint256 rewards) claimableRewardsPerEpoch; // will get set to zero when claimed
}

struct ValidationInfoView {
  uint32 startEpoch;
  uint32 endEpoch;
  uint32 licenseCount;
  uint32 lastUptimeSeconds;
  uint32 lastSubmissionTime;
  uint32 delegationFeeBips;
  address owner;
  uint256 hardwareTokenId;
  bytes registrationMessage;
}

struct DelegationInfo {
  uint32 startEpoch;
  uint32 endEpoch;
  address owner;
  bytes32 validationId;
  uint256[] tokenIds;
  mapping(uint32 epochNumber => uint256 rewards) claimableRewardsPerEpoch; // will get set to zero when claimed
  mapping(uint32 epochNumber => bool passedUptime) uptimeCheck; // will get set to zero when claimed
  EnumerableSet.UintSet claimableEpochNumbers;
}

struct DelegationInfoView {
  uint32 startEpoch;
  uint32 endEpoch;
  address owner;
  bytes32 validationId;
  uint256[] tokenIds;
}

struct NFTStakingManagerSettings {
  bool bypassUptimeCheck; // flag to bypass uptime checks 1 byte
  bool requireHardwareTokenId; // 1 byte

  uint16 uptimePercentage; // 100 = 100% 1 byte
  uint16 maxLicensesPerValidator; // 2 bytes

  uint32 initialEpochTimestamp; // 4 bytes 
  uint32 epochDuration; // 4 bytes
  uint32 gracePeriod; // 4 bytes
  uint64 licenseWeight; // 8 bytes

  uint64 hardwareLicenseWeight; // 8 bytes

  address admin; // 20 bytes
  address validatorManager; // 20 bytes
  address license; // 20 bytes
  address hardwareLicense; // 20 bytes
  uint256 epochRewards; // 32 bytes
}

contract NFTStakingManager is
  Initializable,
  UUPSUpgradeable,
  ContextUpgradeable,
  AccessControlUpgradeable,
  ReentrancyGuardUpgradeable
{
  ///
  /// LIBRARIES
  ///
  using Address for address payable;
  using EnumerableSet for EnumerableSet.UintSet;
  using EnumerableSet for EnumerableSet.Bytes32Set;
  using EnumerableMap for EnumerableMap.AddressToUintMap;

  ///
  /// STORAGE
  ///
  struct NFTStakingManagerStorage {
    bool bypassUptimeCheck; // 1 byte
    uint16 maxLicensesPerValidator; // 100 // 2 bytes
    uint16 uptimePercentage; // 100 = 100% // 2 bytes

    uint32 initialEpochTimestamp; // 1716864000 2024-05-27 00:00:00 UTC  // 4 bytes
    uint32 currentTotalStakedLicenses; // 4 bytes
    uint32 epochDuration; // 1 days // 4 bytes
    uint32 gracePeriod; // starting at 1 hours // 4 bytes

    uint64 licenseWeight; // 1000 // 8 bytes
    uint64 hardwareLicenseWeight; // 1 million // 8 bytes

    ValidatorManager manager; // 20 bytes
    IERC721 licenseContract; // 20 bytes
    IERC721 hardwareLicenseContract; // 20 bytes

    uint256 epochRewards; // 1_369_863 (2_500_000_000 / (365 * 5)) * 1 ether // 32 bytes

    EnumerableSet.Bytes32Set validationIds;
    // We dont xfer nft to this contract, we just mark it as locked
    mapping(uint256 tokenId => bytes32 delegationId) tokenLockedBy;
    mapping(uint256 tokenId => bytes32 validationId) hardwareTokenLockedBy;
    mapping(uint32 epochNumber => EpochInfo) epochs;
    // Ensure that we only ever mint rewards once for a given epochNumber/tokenId combo
    mapping(uint32 epochNumber => mapping(uint256 tokenId => bool isRewardsMinted)) isRewardsMinted;
    // Track prepaid credits for validator hardware service
    mapping(address hardwareOperator => EnumerableMap.AddressToUintMap) prepaidCredits;
    mapping(bytes32 validationId => ValidationInfo) validations;
    mapping(bytes32 delegationId => DelegationInfo) delegations;
    mapping(bytes20 nodeID => NodeInfo) nodes;
  }

  NFTStakingManagerStorage private _storage;

  ///
  /// CONSTANTS
  ///
  IWarpMessenger public constant WARP_MESSENGER =
    IWarpMessenger(0x0200000000000000000000000000000000000005);
  bytes32 public constant NFT_STAKING_MANAGER_STORAGE_LOCATION =
    0xb2bea876b5813e5069ed55d22ad257d01245c883a221b987791b00df2f4dfa00;
  bytes32 public constant PREPAYMENT_ROLE = keccak256("PREPAYMENT_ROLE");

  /// @notice Basis points conversion factor used for percentage calculations (100% = 10000 bips)
  uint256 internal constant BIPS_CONVERSION_FACTOR = 10000;

  ///
  /// EVENTS
  ///
  event DelegationRegistrationInitiated(
    bytes32 indexed validationId, bytes32 indexed delegationId, uint256[] tokenIds
  );
  event DelegationRegistrationCompleted(
    bytes32 indexed validationId, bytes32 indexed delegationId, uint32 startEpoch
  );
  event PrepaidCreditsAdded(
    address indexed hardwareOperator, address indexed licenseHolder, uint32 creditSeconds
  );
  event RewardsMinted(uint32 indexed epochNumber, bytes32 indexed stakeId, uint256 rewards);
  event RewardsClaimed(uint32 indexed epochNumber, bytes32 indexed stakeId, uint256 rewards);
  event TokensLocked(address indexed owner, bytes32 indexed stakeId, uint256[] tokenIds);
  event TokensUnlocked(address indexed owner, bytes32 indexed stakeId, uint256[] tokenIds);

  ///
  /// ERRORS
  ///
  error EpochHasNotEnded();
  error EpochOutOfRange();
  error GracePeriodHasPassed();
  error GracePeriodHasNotPassed();
  error InvalidWarpMessage();
  error InvalidWarpSourceChainID(bytes32 sourceChainID);
  error InvalidWarpOriginSenderAddress(address originSenderAddress);
  error InsufficientUptime();
  error MaxLicensesPerValidatorReached();
  error RewardsAlreadyMintedForTokenId();
  error StakeDoesNotExist();
  error TokenAlreadyLocked(uint256 tokenId);
  error TokenNotLockedByStakeId();
  error UnauthorizedOwner();
  error ValidationIDMismatch();
  error ValidatorHasEnded();
  error ValidatorRegistrationNotComplete();
  error ZeroAddress();

  /// @notice disable initializers if constructed directly
  constructor() {
    _disableInitializers();
  }

  function initialize(NFTStakingManagerSettings calldata settings) external initializer {
    UUPSUpgradeable.__UUPSUpgradeable_init();
    ContextUpgradeable.__Context_init();
    AccessControlUpgradeable.__AccessControl_init();
    ReentrancyGuardUpgradeable.__ReentrancyGuard_init();

    __NFTStakingManager_init(settings);
  }

  function __NFTStakingManager_init(NFTStakingManagerSettings calldata settings)
    internal
    onlyInitializing
  {
    if (settings.admin == address(0)) revert ZeroAddress();
    _grantRole(DEFAULT_ADMIN_ROLE, settings.admin);

    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();

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
    $.uptimePercentage = settings.uptimePercentage;
    $.bypassUptimeCheck = settings.bypassUptimeCheck;
  }

  ///
  /// VALIDATOR FUNCTIONS
  ///
  function initiateValidatorRegistration(
    bytes memory nodeID,
    bytes memory blsPublicKey,
    bytes memory blsPoP,
    PChainOwner memory remainingBalanceOwner,
    PChainOwner memory disableOwner,
    uint256 hardwareTokenId,
    uint32 delegationFeeBips
  ) public returns (bytes32) {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    bytes32 validationId = $.manager.initiateValidatorRegistration(
      nodeID, blsPublicKey, remainingBalanceOwner, disableOwner, $.hardwareLicenseWeight
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
        registrationExpiry: uint64(block.timestamp) + $.manager.REGISTRATION_EXPIRY_LENGTH(),
        weight: $.hardwareLicenseWeight
      })
    );

    ValidationInfo storage validation = $.validations[validationId];
    validation.owner = _msgSender();
    validation.startEpoch = getCurrentEpoch();
    validation.hardwareTokenId = hardwareTokenId;
    validation.registrationMessage = registerL1ValidatorMessage;
    validation.lastSubmissionTime = getEpochEndTime(getCurrentEpoch() - 1);
    validation.delegationFeeBips = delegationFeeBips;

    // The blsPoP is required to complete the validator registration on the P-Chain, so store it here
    // for an off-chain service to use to complete the registration.
    bytes20 fixedNodeID = _fixedNodeID(nodeID);
    $.nodes[fixedNodeID] =
      NodeInfo({ owner: _msgSender(), blsPublicKey: blsPublicKey, blsPoP: blsPoP });

    return validationId;
  }

  /// @notice Complete validator registration
  ///
  /// @param messageIndex The index of the message to complete the validator registration
  ///
  /// @return validationId The unique identifier for this validator registration
  function completeValidatorRegistration(uint32 messageIndex) external returns (bytes32) {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    bytes32 validationId = $.manager.completeValidatorRegistration(messageIndex);

    ValidationInfo storage validation = $.validations[validationId];
    validation.startEpoch = getCurrentEpoch();
    return validationId;
  }

  // TODO How to handle the original 5 PoA validators?
  // Ava lets anyone remove the original 5
  // https://github.com/ava-labs/icm-contracts/blob/main/contracts/validator-manager/StakingManager.sol#L377
  // we would check if validations[validaionId].owner == address(0) then its a PoA validator
  // maybe we have a seperate func onlyAdmin that can remove the PoA validators.
  // AND DO NOT let people delegate to them.

  function initiateValidatorRemoval(bytes32 validationId) external {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    ValidationInfo storage validation = $.validations[validationId];
    if (validation.owner != _msgSender()) revert UnauthorizedOwner();
    validation.endEpoch = getCurrentEpoch();
    $.manager.initiateValidatorRemoval(validationId);
    // TODO: remove delegators. This might be gas intensive, so also have a way for validators to
    // remove an array of delegationIds. Once they remove those then they can end their validation period.
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
    // TODO Should we delete? What if validator leaves during grace period, if we delete then they are not included in the rewards
    // maybe keep around and remove during rewards payouts.
    delete $.validations[validationId];
    $.validationIds.remove(validationId);
    return validationId;
  }

  /// @notice callable by the delagtor to stake node licenses
  /// @param validationId the validation id of the validator
  /// @param tokenIds the token ids of the licenses to stake
  /// @return the delegation id
  function initiateDelegatorRegistration(bytes32 validationId, uint256[] calldata tokenIds)
    public
    returns (bytes32)
  {
    // TODO: consider checking if the sender owns the tokensids here
    // or check in _lockTokens method
    return _initiateDelegatorRegistration(validationId, _msgSender(), tokenIds);
  }

  /// @notice callable by the validation owner to stake node licenses on behalf of the delagtor
  /// @param validationId the validation id of the validator
  /// @param owner the owner of the licenses
  /// @param tokenIds the token ids of the licenses to stake
  /// @return the delegation id
  function initiateDelegatorRegistrationOnBehalfOf(
    bytes32 validationId,
    address owner,
    uint256[] calldata tokenIds
  ) public returns (bytes32) {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    ValidationInfo storage validation = $.validations[validationId];

    if (validation.owner != _msgSender()) {
      revert UnauthorizedOwner();
    }

    bool isApprovedForAll = $.licenseContract.isApprovedForAll(owner, _msgSender());

    // If no blanket approval, check each token individually
    if (!isApprovedForAll) {
      for (uint256 i = 0; i < tokenIds.length; i++) {
        if ($.licenseContract.getApproved(tokenIds[i]) != _msgSender()) {
          revert UnauthorizedOwner();
        }
      }
    }

    return _initiateDelegatorRegistration(validationId, owner, tokenIds);
  }

  /// @notice internal function to initiate a delegation
  /// @param validationId the validation id of the validator
  /// @param owner the owner of the licenses
  /// @param tokenIds the token ids of the licenses to stake
  /// @return the delegation id
  function _initiateDelegatorRegistration(
    bytes32 validationId,
    address owner,
    uint256[] calldata tokenIds
  ) internal returns (bytes32) {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    ValidationInfo storage validation = $.validations[validationId];

    // TODO: is this check necessary? Verify ownership of all tokens
    for (uint256 i = 0; i < tokenIds.length; i++) {
      if ($.licenseContract.ownerOf(tokenIds[i]) != owner) {
        revert UnauthorizedOwner();
      }
    }

    if (validation.endEpoch != 0) {
      revert ValidatorHasEnded();
    }
    if (validation.startEpoch == 0 || validation.startEpoch > getCurrentEpoch()) {
      revert ValidatorRegistrationNotComplete();
    }
    validation.licenseCount += uint32(tokenIds.length);
    if (validation.licenseCount > $.maxLicensesPerValidator) {
      revert MaxLicensesPerValidatorReached();
    }

    Validator memory validator = $.manager.getValidator(validationId);
    uint64 newWeight = validator.weight + _getWeight(tokenIds.length);
    (uint64 nonce,) = $.manager.initiateValidatorWeightUpdate(validationId, newWeight);

    bytes32 delegationId = keccak256(abi.encodePacked(validationId, nonce));

    validation.delegationIds.add(delegationId);

    _lockTokens(delegationId, tokenIds);

    DelegationInfo storage newDelegation = $.delegations[delegationId];
    newDelegation.owner = owner;
    newDelegation.tokenIds = tokenIds;
    newDelegation.validationId = validationId;

    emit DelegationRegistrationInitiated(validationId, delegationId, tokenIds);
    return delegationId;
  }

  function completeDelegatorRegistration(bytes32 delegationId, uint32 messageIndex) public {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    (bytes32 validationId,) = $.manager.completeValidatorWeightUpdate(messageIndex);
    DelegationInfo storage delegation = $.delegations[delegationId];
    if (validationId != delegation.validationId) {
      revert ValidationIDMismatch();
    }
    // TODO: do we incrememnt here or in the initiate call?
    // validation.licenseCount += uint32(delegation.tokenIds.length);

    delegation.startEpoch = getCurrentEpoch();
    emit DelegationRegistrationCompleted(validationId, delegationId, delegation.startEpoch);
  }

  // TODO enforce a min duration?
  function initiateDelegatorRemoval(bytes32 delegationId) external {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();

    DelegationInfo storage delegation = $.delegations[delegationId];
    ValidationInfo storage validation = $.validations[delegation.validationId];
    Validator memory validator = $.manager.getValidator(delegation.validationId);

    if (delegation.owner != _msgSender()) revert UnauthorizedOwner();

    // TODO figure out which vars to update now and which after the weight update

    // End the delegation as of the prev epoch, so users will not receive rewards for the current epoch
    // as they were not present for the whole epoch duration
    delegation.endEpoch = getCurrentEpoch() - 1;
    validation.licenseCount -= uint32(delegation.tokenIds.length);
    uint64 newWeight = validator.weight - _getWeight(delegation.tokenIds.length);
    // Do not delete delegation yet, we need it to pay out rewards in the case that a delegator leaves
    // during the grace period when proofs are being submitted
    // validation.delegationIds.remove(delegationId);

    // (uint64 nonce,) = $.manager.initiateValidatorWeightUpdate(delegation.validationId, newWeight);
    $.manager.initiateValidatorWeightUpdate(delegation.validationId, newWeight);
    // TODO figure out nonces. each weight update for a validationid has a unique nonce.
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
      revert ValidationIDMismatch();
    }

    _unlockTokens(delegationId, $.delegations[delegationId].tokenIds);

    return delegationId;
  }

  // Hardware Operators can accept payment for hardware service off-chain,
  // and record the user's credits here
  function addPrepaidCredits(address licenseHolder, uint32 creditSeconds)
    external
    onlyRole(PREPAYMENT_ROLE)
  {
    address hardwareOperator = _msgSender();
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    (, uint256 currentCredits) = $.prepaidCredits[hardwareOperator].tryGet(licenseHolder);
    $.prepaidCredits[hardwareOperator].set(licenseHolder, currentCredits + creditSeconds);
    emit PrepaidCreditsAdded(hardwareOperator, licenseHolder, creditSeconds);
  }

  function processProof(uint32 messageIndex) public {
    bytes32 uptimeBlockchainID = 0x0000000000000000000000000000000000000000000000000000000000000000;
    (bytes32 validationId, uint64 uptimeSeconds) = ValidatorMessages.unpackValidationUptimeMessage(
      _getPChainWarpMessage(messageIndex, uptimeBlockchainID).payload
    );

    uint32 epoch = getEpochByTimestamp(uint32(block.timestamp));
    epoch--;
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    if (epoch == 0) {
      revert EpochHasNotEnded();
    }

    if (block.timestamp >= getEpochEndTime(epoch) + $.gracePeriod) {
      revert GracePeriodHasPassed();
    }

    ValidationInfo storage validation = $.validations[validationId];

    // TODO just init these values when the validator is registered

    if (!$.bypassUptimeCheck) {
      uint32 lastSubmissionTime = validation.lastSubmissionTime;
      uint32 lastUptimeSeconds = validation.lastUptimeSeconds;

      uint32 uptimeDelta = uint32(uptimeSeconds) - lastUptimeSeconds;
      uint32 submissionTimeDelta = uint32(block.timestamp) - lastSubmissionTime;
      uint256 effectiveUptime = uint256(uptimeDelta) * $.epochDuration / submissionTimeDelta;
      if (effectiveUptime < _expectedUptime()) {
        revert InsufficientUptime();
      }

      // Only update state if uptime check passes
      validation.lastUptimeSeconds = uint32(uptimeSeconds);
      validation.lastSubmissionTime = uint32(block.timestamp);
    }

    EpochInfo storage epochInfo = $.epochs[epoch];

    // then for each delegation that was on the active validator, record that they can get rewards
    for (uint256 i = 0; i < validation.delegationIds.length(); i++) {
      bytes32 delegationId = validation.delegationIds.at(i);
      DelegationInfo storage delegation = $.delegations[delegationId];
      delegation.uptimeCheck[epoch] = true;
      epochInfo.totalStakedLicenses += delegation.tokenIds.length;
    }
  }

  function mintRewards(bytes32[] calldata validationIds, uint32 epoch) external {
    for (uint256 i = 0; i < validationIds.length; i++) {
      mintRewards(validationIds[i], epoch);
    }
  }

  function mintRewards(bytes32 validationId, uint32 epoch) public {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    ValidationInfo storage validation = $.validations[validationId];

    if (block.timestamp <= getEpochEndTime(epoch) + $.gracePeriod) {
      revert GracePeriodHasNotPassed();
    }

    uint256 totalDelegations = validation.delegationIds.length();

    for (uint256 i = 0; i < totalDelegations; i++) {
      bytes32 delegationId = validation.delegationIds.at(i);
      DelegationInfo storage delegation = $.delegations[delegationId];
      // TODO: revist this epoch check
      if (delegation.uptimeCheck[epoch] && epoch >= delegation.startEpoch) {
        mintDelegatorRewards(epoch, delegationId);
      }
    }
  }

  // verify that the user had a valid uptime for the given epcoh
  // TODO epoch is always the prev epoch, so dont pass in.
  function mintDelegatorRewards(uint32 epoch, bytes32 delegationId) public {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    DelegationInfo storage delegation = $.delegations[delegationId];
    ValidationInfo storage validation = $.validations[delegation.validationId];

    if (delegation.owner == address(0)) {
      revert StakeDoesNotExist();
    }

    if (epoch < delegation.startEpoch || (epoch > delegation.endEpoch && delegation.endEpoch != 0))
    {
      revert EpochOutOfRange();
    }

    if (delegation.endEpoch != 0) {
      // The delegator will be paid out for the last epoch, but has ended, so delete it now
      // If we leave old ones in then they will pile up and make looping over everything more costly
      validation.delegationIds.remove(delegationId);
      // TODO The delegation data we could keep? For historical querying?
      // delete $.delegations[delegationId];
    }

    for (uint256 i = 0; i < delegation.tokenIds.length; i++) {
      // TODO if either of these happen it seems unrecoverable? How would we fix?
      // admin fn to manually add data to rewards and locked mappings?
      if ($.tokenLockedBy[delegation.tokenIds[i]] != delegationId) {
        revert TokenNotLockedByStakeId();
      }
      if ($.isRewardsMinted[epoch][delegation.tokenIds[i]]) {
        revert RewardsAlreadyMintedForTokenId();
      }

      $.isRewardsMinted[epoch][delegation.tokenIds[i]] = true;
    }

    // If the license holder has prepaid credits, deduct them.
    // How many tokens can they pay for for a full epoch?
    // If there are no credits left, all remaining tokens will pay a delegation fee to validator
    (, uint256 creditSeconds) = $.prepaidCredits[validation.owner].tryGet(delegation.owner);
    uint256 prepaidTokenCount = creditSeconds / $.epochDuration;
    prepaidTokenCount = prepaidTokenCount > delegation.tokenIds.length
      ? delegation.tokenIds.length
      : prepaidTokenCount;
    uint256 delegationFeeTokenCount = delegation.tokenIds.length - prepaidTokenCount;
    $.prepaidCredits[validation.owner].set(
      delegation.owner, creditSeconds - prepaidTokenCount * $.epochDuration
    );

    uint256 rewardsPerLicense = calculateRewardsPerLicense(epoch);
    uint256 totalRewards = delegation.tokenIds.length * rewardsPerLicense;
    uint256 delegationFee = delegationFeeTokenCount * rewardsPerLicense
      * validation.delegationFeeBips / BIPS_CONVERSION_FACTOR;
    validation.claimableRewardsPerEpoch[epoch] += delegationFee;
    uint256 rewards = totalRewards - delegationFee;
    delegation.claimableRewardsPerEpoch[epoch] = rewards;
    delegation.claimableEpochNumbers.add(uint256(epoch));
    // TODO prob should return rwds amt then mint once the whole amount in the fn above
    INativeMinter(0x0200000000000000000000000000000000000001).mintNativeCoin(address(this), rewards);
    emit RewardsMinted(epoch, delegationId, rewards);
  }

  function claimRewards(bytes32 delegationId, uint32 maxEpochs)
    external
    returns (uint256, uint32[] memory)
  {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    DelegationInfo storage delegation = $.delegations[delegationId];

    if (delegation.owner != _msgSender()) revert UnauthorizedOwner();
    if (maxEpochs > delegation.claimableEpochNumbers.length()) {
      maxEpochs = uint32(delegation.claimableEpochNumbers.length());
    }

    uint256 totalRewards = 0;
    uint32[] memory claimedEpochNumbers = new uint32[](maxEpochs);

    for (uint32 i = 0; i < maxEpochs; i++) {
      uint32 epochNumber = uint32(delegation.claimableEpochNumbers.at(0));
      uint256 rewards = delegation.claimableRewardsPerEpoch[epochNumber];

      // State changes
      claimedEpochNumbers[i] = epochNumber;
      totalRewards += rewards;
      // this remove updates the array indicies. so always remove item 0
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

  ///
  /// ADMIN FUNCTIONS
  ///
  function setBypassUptimeCheck(bool bypass) external onlyRole(DEFAULT_ADMIN_ROLE) {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    $.bypassUptimeCheck = bypass;
  }

  function calculateRewardsPerLicense(uint32 epochNumber) internal view returns (uint256) {
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

  function getEpochEndTime(uint32 epoch) public view returns (uint32) {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    return $.initialEpochTimestamp + (epoch * $.epochDuration);
  }

  function getEpochInfo(uint32 epoch) external view returns (EpochInfo memory) {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    return $.epochs[epoch];
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
      registrationMessage: validation.registrationMessage,
      lastUptimeSeconds: validation.lastUptimeSeconds,
      lastSubmissionTime: validation.lastSubmissionTime,
      delegationFeeBips: validation.delegationFeeBips
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

  function _expectedUptime() internal view returns (uint256) {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    return $.epochDuration * $.uptimePercentage / 100;
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
      // TODO: Do we need this chekc? or a different call that verifies the owner trying to lock the tokens owns the token
      // we move the burden of chekcing the approval from this function to the caller
      // if (owner != _msgSender()) revert UnauthorizedOwner(owner);
      if ($.tokenLockedBy[tokenId] != bytes32(0)) revert TokenAlreadyLocked(tokenId);
      $.tokenLockedBy[tokenId] = stakeId;
    }
    emit TokensLocked(owner, stakeId, tokenIds);
  }

  function _lockHardwareToken(bytes32 stakeId, uint256 tokenId) internal {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    address owner = $.hardwareLicenseContract.ownerOf(tokenId);
    if (owner != _msgSender()) revert UnauthorizedOwner();
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

  function _getPChainWarpMessage(uint32 messageIndex, bytes32 expectedSourceChainID)
    internal
    view
    returns (WarpMessage memory)
  {
    (WarpMessage memory warpMessage, bool valid) =
      WARP_MESSENGER.getVerifiedWarpMessage(messageIndex);
    if (!valid) {
      revert InvalidWarpMessage();
    }
    // Must match to P-Chain blockchain id, which is 0.
    if (warpMessage.sourceChainID != expectedSourceChainID) {
      revert InvalidWarpSourceChainID(warpMessage.sourceChainID);
    }
    if (warpMessage.originSenderAddress != address(0)) {
      revert InvalidWarpOriginSenderAddress(warpMessage.originSenderAddress);
    }

    return warpMessage;
  }

  /// @notice Converts a nodeID to a fixed length of 20 bytes.
  /// @param nodeID The nodeID to convert.
  /// @return The fixed length nodeID.
  function _fixedNodeID(bytes memory nodeID) private pure returns (bytes20) {
    bytes20 fixedID;
    // solhint-disable-next-line no-inline-assembly
    assembly {
      fixedID := mload(add(nodeID, 32))
    }
    return fixedID;
  }

  /// @notice Authorizes upgrade to DEFAULT_ADMIN_ROLE
  function _authorizeUpgrade(address newImplementation)
    internal
    override
    onlyRole(DEFAULT_ADMIN_ROLE)
  { }
}
