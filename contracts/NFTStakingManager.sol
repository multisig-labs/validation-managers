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

struct ValidationInfo {
  uint32 startEpoch; // 4 bytes
  uint32 endEpoch; // 4 bytes
  uint32 licenseCount; // 4 bytes
  uint32 lastUptimeSeconds; // 4 bytes
  uint32 lastSubmissionTime; // 4 bytes
  uint32 delegationFeeBips; // 4 bytes
  address owner; // 20 bytes
  uint256 hardwareTokenID; // 32 bytes
  bytes registrationMessage; // 32 bytes
  EnumerableSet.Bytes32Set delegationIDs;
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
  uint256 hardwareTokenID;
  bytes registrationMessage;
}

struct DelegationInfo {
  uint32 startEpoch;
  uint32 endEpoch;
  address owner;
  bytes32 validationID;
  uint256[] tokenIDs;
  mapping(uint32 epochNumber => uint256 rewards) claimableRewardsPerEpoch; // will get set to zero when claimed
  mapping(uint32 epochNumber => bool passedUptime) uptimeCheck; // will get set to zero when claimed
  EnumerableSet.UintSet claimableEpochNumbers;
}

struct DelegationInfoView {
  uint32 startEpoch;
  uint32 endEpoch;
  address owner;
  bytes32 validationID;
  uint256[] tokenIDs;
}

struct NFTStakingManagerSettings {
  bool bypassUptimeCheck; // flag to bypass uptime checks 1 byte
  bool requireHardwareTokenID; // 1 byte
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
    EnumerableSet.Bytes32Set validationIDs;
    // We dont xfer nft to this contract, we just mark it as locked
    mapping(uint256 tokenID => bytes32 delegationID) tokenLockedBy;
    mapping(uint256 tokenID => bytes32 validationID) hardwareTokenLockedBy;
    mapping(uint32 epochNumber => EpochInfo) epochs;
    // Ensure that we only ever mint rewards once for a given epochNumber/tokenID combo
    mapping(uint32 epochNumber => mapping(uint256 tokenID => bool isRewardsMinted)) isRewardsMinted;
    // Track prepaid credits for validator hardware service
    mapping(address hardwareOperator => EnumerableMap.AddressToUintMap) prepaidCredits;
    mapping(bytes32 validationID => ValidationInfo) validations;
    mapping(bytes32 delegationID => DelegationInfo) delegations;
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
  event InitiatedValidatorRegistration(
    bytes32 indexed validationID, uint256 hardwareTokenID, bytes blsPoP
  );
  event CompletedValidatorRegistration(bytes32 indexed validationID, uint32 startEpoch);
  event InitiatedValidatorRemoval(bytes32 validationID, uint256 hardwareTokenID, uint32 endEpoch);
  event CompletedValidatorRemoval(bytes32 validationID);
  event InitiatedDelegatorRegistration(
    bytes32 indexed validationID, bytes32 indexed delegationID, uint256[] tokenIDs
  );
  event CompletedDelegatorRegistration(
    bytes32 indexed validationID, bytes32 indexed delegationID, uint64 nonce, uint32 startEpoch
  );
  event InitiatedDelegatorRemoval(
    bytes32 indexed validationID, bytes32 indexed delegationID, uint256[] tokenIDs, uint32 endEpoch
  );
  event CompletedDelegatorRemoval(
    bytes32 indexed validationID, bytes32 indexed delegationID, uint64 nonce
  );
  event PrepaidCreditsAdded(
    address indexed hardwareOperator, address indexed licenseHolder, uint32 creditSeconds
  );
  event RewardsClaimed(uint32 indexed epochNumber, bytes32 indexed delegationID, uint256 rewards);
  event RewardsMinted(uint32 indexed epochNumber, bytes32 indexed delegationID, uint256 rewards);
  event TokensLocked(address indexed owner, bytes32 indexed delegationID, uint256[] tokenIDs);
  event TokensUnlocked(address indexed owner, bytes32 indexed delegationID, uint256[] tokenIDs);

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
  error RewardsAlreadyMintedFortokenID();
  error StakeDoesNotExist();
  error TokenAlreadyLocked(uint256 tokenID);
  error TokenNotLockedBydelegationID();
  error UnauthorizedOwner();
  error validationIDMismatch();
  error delegationIDMismatch();
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
    uint256 hardwareTokenID,
    uint32 delegationFeeBips
  ) public returns (bytes32) {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    bytes32 validationID = $.manager.initiateValidatorRegistration(
      nodeID, blsPublicKey, remainingBalanceOwner, disableOwner, $.hardwareLicenseWeight
    );

    _lockHardwareToken(validationID, hardwareTokenID);

    $.validationIDs.add(validationID);

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

    ValidationInfo storage validation = $.validations[validationID];
    validation.owner = _msgSender();
    validation.startEpoch = getCurrentEpoch();
    validation.hardwareTokenID = hardwareTokenID;
    validation.registrationMessage = registerL1ValidatorMessage;
    validation.lastSubmissionTime = getEpochEndTime(getCurrentEpoch() - 1);
    validation.delegationFeeBips = delegationFeeBips;

    // The blsPoP is required to complete the validator registration on the P-Chain, so emit it here
    emit InitiatedValidatorRegistration(validationID, validation.hardwareTokenID, blsPoP);

    return validationID;
  }

  /// @notice Complete validator registration
  ///
  /// @param messageIndex The index of the message to complete the validator registration
  ///
  /// @return validationID The unique identifier for this validator registration
  function completeValidatorRegistration(uint32 messageIndex) external returns (bytes32) {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    bytes32 validationID = $.manager.completeValidatorRegistration(messageIndex);

    ValidationInfo storage validation = $.validations[validationID];
    validation.startEpoch = getCurrentEpoch();
    emit CompletedValidatorRegistration(validationID, validation.startEpoch);
    return validationID;
  }

  // TODO How to handle the original 5 PoA validators?
  // Ava lets anyone remove the original 5
  // https://github.com/ava-labs/icm-contracts/blob/main/contracts/validator-manager/StakingManager.sol#L377
  // we would check if validations[validaionId].owner == address(0) then its a PoA validator
  // maybe we have a seperate func onlyAdmin that can remove the PoA validators.
  // AND DO NOT let people delegate to them.

  function initiateValidatorRemoval(bytes32 validationID) external {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    ValidationInfo storage validation = $.validations[validationID];
    if (validation.owner != _msgSender()) revert UnauthorizedOwner();
    validation.endEpoch = getCurrentEpoch();
    $.manager.initiateValidatorRemoval(validationID);
    // TODO: remove delegators. This might be gas intensive, so also have a way for validators to
    // remove an array of delegationIDs. Once they remove those then they can end their validation period.
    emit InitiatedValidatorRemoval(validationID, validation.hardwareTokenID, validation.endEpoch);
  }

  function completeValidatorRemoval(bytes32 validationID, uint32 messageIndex)
    external
    returns (bytes32)
  {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    ValidationInfo storage validation = $.validations[validationID];

    $.manager.completeValidatorRemoval(messageIndex);

    _unlockHardwareToken(validation.hardwareTokenID);

    for (uint256 i = 0; i < validation.delegationIDs.length(); i++) {
      bytes32 delegationID = validation.delegationIDs.at(i);
      _unlockTokens(delegationID, $.delegations[delegationID].tokenIDs);
    }

    emit CompletedValidatorRemoval(validationID);

    // TODO Should we delete? What if validator leaves during grace period, if we delete then they are not included in the rewards
    // maybe keep around and remove during rewards payouts.
    delete $.validations[validationID];
    $.validationIDs.remove(validationID);
    return validationID;
  }

  /// @notice callable by the delagtor to stake node licenses
  /// @param validationID the validation id of the validator
  /// @param tokenIDs the token ids of the licenses to stake
  /// @return the delegation id
  function initiateDelegatorRegistration(bytes32 validationID, uint256[] calldata tokenIDs)
    public
    returns (bytes32)
  {
    // TODO: consider checking if the sender owns the tokensids here
    // or check in _lockTokens method
    return _initiateDelegatorRegistration(validationID, _msgSender(), tokenIDs);
  }

  /// @notice callable by the validation owner to stake node licenses on behalf of the delagtor
  /// @param validationID the validation id of the validator
  /// @param owner the owner of the licenses
  /// @param tokenIDs the token ids of the licenses to stake
  /// @return the delegation id
  function initiateDelegatorRegistrationOnBehalfOf(
    bytes32 validationID,
    address owner,
    uint256[] calldata tokenIDs
  ) public returns (bytes32) {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    ValidationInfo storage validation = $.validations[validationID];

    if (validation.owner != _msgSender()) {
      revert UnauthorizedOwner();
    }

    bool isApprovedForAll = $.licenseContract.isApprovedForAll(owner, _msgSender());

    // If no blanket approval, check each token individually
    if (!isApprovedForAll) {
      for (uint256 i = 0; i < tokenIDs.length; i++) {
        if ($.licenseContract.getApproved(tokenIDs[i]) != _msgSender()) {
          revert UnauthorizedOwner();
        }
      }
    }

    return _initiateDelegatorRegistration(validationID, owner, tokenIDs);
  }

  /// @notice internal function to initiate a delegation
  /// @param validationID the validation id of the validator
  /// @param owner the owner of the licenses
  /// @param tokenIDs the token ids of the licenses to stake
  /// @return the delegation id
  function _initiateDelegatorRegistration(
    bytes32 validationID,
    address owner,
    uint256[] calldata tokenIDs
  ) internal returns (bytes32) {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    ValidationInfo storage validation = $.validations[validationID];

    // TODO: is this check necessary? Verify ownership of all tokens
    for (uint256 i = 0; i < tokenIDs.length; i++) {
      if ($.licenseContract.ownerOf(tokenIDs[i]) != owner) {
        revert UnauthorizedOwner();
      }
    }

    if (validation.endEpoch != 0) {
      revert ValidatorHasEnded();
    }
    if (validation.startEpoch == 0 || validation.startEpoch > getCurrentEpoch()) {
      revert ValidatorRegistrationNotComplete();
    }
    validation.licenseCount += uint32(tokenIDs.length);
    if (validation.licenseCount > $.maxLicensesPerValidator) {
      revert MaxLicensesPerValidatorReached();
    }

    Validator memory validator = $.manager.getValidator(validationID);
    uint64 newWeight = validator.weight + $.licenseWeight * uint64(tokenIDs.length);
    (uint64 nonce,) = $.manager.initiateValidatorWeightUpdate(validationID, newWeight);

    bytes32 delegationID = keccak256(abi.encodePacked(validationID, nonce));

    validation.delegationIDs.add(delegationID);

    _lockTokens(delegationID, tokenIDs);

    DelegationInfo storage newDelegation = $.delegations[delegationID];
    newDelegation.owner = owner;
    newDelegation.tokenIDs = tokenIDs;
    newDelegation.validationID = validationID;

    emit InitiatedDelegatorRegistration(validationID, delegationID, tokenIDs);
    return delegationID;
  }

  function completeDelegatorRegistration(bytes32 delegationID, uint32 messageIndex) public {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    (bytes32 validationID, uint64 nonce) = $.manager.completeValidatorWeightUpdate(messageIndex);
    DelegationInfo storage delegation = $.delegations[delegationID];
    if (validationID != delegation.validationID) {
      revert validationIDMismatch();
    }

    // TODO: do we incrememnt here or in the initiate call?
    // validation.licenseCount += uint32(delegation.tokenIDs.length);

    delegation.startEpoch = getCurrentEpoch();
    emit CompletedDelegatorRegistration(validationID, delegationID, nonce, delegation.startEpoch);
  }

  // TODO enforce a min duration?
  function initiateDelegatorRemoval(bytes32 delegationID) external {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();

    DelegationInfo storage delegation = $.delegations[delegationID];
    ValidationInfo storage validation = $.validations[delegation.validationID];
    Validator memory validator = $.manager.getValidator(delegation.validationID);

    if (delegation.owner != _msgSender()) revert UnauthorizedOwner();

    // TODO figure out which vars to update now and which after the weight update

    // End the delegation as of the prev epoch, so users will not receive rewards for the current epoch
    // as they were not present for the whole epoch duration
    delegation.endEpoch = getCurrentEpoch() - 1;
    validation.licenseCount -= uint32(delegation.tokenIDs.length);
    uint64 newWeight = validator.weight - $.licenseWeight * uint64(delegation.tokenIDs.length);
    // Do not delete delegation yet, we need it to pay out rewards in the case that a delegator leaves
    // during the grace period when proofs are being submitted
    // validation.delegationIDs.remove(delegationID);

    // (uint64 nonce,) = $.manager.initiateValidatorWeightUpdate(delegation.validationID, newWeight);
    $.manager.initiateValidatorWeightUpdate(delegation.validationID, newWeight);
    // TODO figure out nonces. each weight update for a validationID has a unique nonce.
    emit InitiatedDelegatorRemoval(
      delegation.validationID, delegationID, delegation.tokenIDs, delegation.endEpoch
    );
  }

  function completeDelegatorRemoval(bytes32 delegationID, uint32 messageIndex)
    external
    returns (bytes32)
  {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();

    // Complete the weight update
    // TODO I think this allows anyone to use the "wrong" delegationID? Maybe need a "pending" state
    // we set before, then check it here?
    (bytes32 validationID, uint64 nonce) = $.manager.completeValidatorWeightUpdate(messageIndex);
    if (validationID != $.delegations[delegationID].validationID) {
      revert validationIDMismatch();
    }

    _unlockTokens(delegationID, $.delegations[delegationID].tokenIDs);
    emit CompletedDelegatorRemoval(validationID, delegationID, nonce);
    return delegationID;
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
    (bytes32 validationID, uint64 uptimeSeconds) = ValidatorMessages.unpackValidationUptimeMessage(
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

    ValidationInfo storage validation = $.validations[validationID];

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
    for (uint256 i = 0; i < validation.delegationIDs.length(); i++) {
      bytes32 delegationID = validation.delegationIDs.at(i);
      DelegationInfo storage delegation = $.delegations[delegationID];
      delegation.uptimeCheck[epoch] = true;
      epochInfo.totalStakedLicenses += delegation.tokenIDs.length;
    }
  }

  function mintRewards(bytes32[] calldata validationIDs, uint32 epoch) external {
    for (uint256 i = 0; i < validationIDs.length; i++) {
      mintRewards(validationIDs[i], epoch);
    }
  }

  function mintRewards(bytes32 validationID, uint32 epoch) public {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    ValidationInfo storage validation = $.validations[validationID];

    if (block.timestamp <= getEpochEndTime(epoch) + $.gracePeriod) {
      revert GracePeriodHasNotPassed();
    }

    uint256 totalDelegations = validation.delegationIDs.length();

    for (uint256 i = 0; i < totalDelegations; i++) {
      bytes32 delegationID = validation.delegationIDs.at(i);
      DelegationInfo storage delegation = $.delegations[delegationID];
      // TODO: revist this epoch check
      if (delegation.uptimeCheck[epoch] && epoch >= delegation.startEpoch) {
        mintDelegatorRewards(epoch, delegationID);
      }
    }
  }

  // verify that the user had a valid uptime for the given epcoh
  // TODO epoch is always the prev epoch, so dont pass in.
  function mintDelegatorRewards(uint32 epoch, bytes32 delegationID) public {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    DelegationInfo storage delegation = $.delegations[delegationID];
    ValidationInfo storage validation = $.validations[delegation.validationID];

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
      validation.delegationIDs.remove(delegationID);
      // TODO The delegation data we could keep? For historical querying?
      // delete $.delegations[delegationID];
    }

    for (uint256 i = 0; i < delegation.tokenIDs.length; i++) {
      // TODO if either of these happen it seems unrecoverable? How would we fix?
      // admin fn to manually add data to rewards and locked mappings?
      if ($.tokenLockedBy[delegation.tokenIDs[i]] != delegationID) {
        revert TokenNotLockedBydelegationID();
      }
      if ($.isRewardsMinted[epoch][delegation.tokenIDs[i]]) {
        revert RewardsAlreadyMintedFortokenID();
      }

      $.isRewardsMinted[epoch][delegation.tokenIDs[i]] = true;
    }

    // If the license holder has prepaid credits, deduct them.
    // How many tokens can they pay for for a full epoch?
    // If there are no credits left, all remaining tokens will pay a delegation fee to validator
    (, uint256 creditSeconds) = $.prepaidCredits[validation.owner].tryGet(delegation.owner);
    uint256 prepaidTokenCount = creditSeconds / $.epochDuration;
    prepaidTokenCount = prepaidTokenCount > delegation.tokenIDs.length
      ? delegation.tokenIDs.length
      : prepaidTokenCount;
    uint256 delegationFeeTokenCount = delegation.tokenIDs.length - prepaidTokenCount;
    $.prepaidCredits[validation.owner].set(
      delegation.owner, creditSeconds - prepaidTokenCount * $.epochDuration
    );

    uint256 rewardsPerLicense = calculateRewardsPerLicense(epoch);
    uint256 totalRewards = delegation.tokenIDs.length * rewardsPerLicense;
    uint256 delegationFee = delegationFeeTokenCount * rewardsPerLicense
      * validation.delegationFeeBips / BIPS_CONVERSION_FACTOR;
    validation.claimableRewardsPerEpoch[epoch] += delegationFee;
    uint256 rewards = totalRewards - delegationFee;
    delegation.claimableRewardsPerEpoch[epoch] = rewards;
    delegation.claimableEpochNumbers.add(uint256(epoch));
    // TODO prob should return rwds amt then mint once the whole amount in the fn above
    INativeMinter(0x0200000000000000000000000000000000000001).mintNativeCoin(address(this), rewards);
    emit RewardsMinted(epoch, delegationID, rewards);
  }

  function claimRewards(bytes32 delegationID, uint32 maxEpochs)
    external
    returns (uint256, uint32[] memory)
  {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    DelegationInfo storage delegation = $.delegations[delegationID];

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
        delegationID,
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

  function getTokenLockedBy(uint256 tokenID) external view returns (bytes32) {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    return $.tokenLockedBy[tokenID];
  }

  function getvalidationIDs() external view returns (bytes32[] memory) {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    return $.validationIDs.values();
  }

  function getDelegationInfoView(bytes32 delegationID)
    external
    view
    returns (DelegationInfoView memory)
  {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    DelegationInfo storage delegation = $.delegations[delegationID];
    return DelegationInfoView({
      owner: delegation.owner,
      validationID: delegation.validationID,
      startEpoch: delegation.startEpoch,
      endEpoch: delegation.endEpoch,
      tokenIDs: delegation.tokenIDs
    });
  }

  function getValidationInfoView(bytes32 validationID)
    external
    view
    returns (ValidationInfoView memory)
  {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    ValidationInfo storage validation = $.validations[validationID];
    return ValidationInfoView({
      owner: validation.owner,
      hardwareTokenID: validation.hardwareTokenID,
      startEpoch: validation.startEpoch,
      endEpoch: validation.endEpoch,
      licenseCount: validation.licenseCount,
      registrationMessage: validation.registrationMessage,
      lastUptimeSeconds: validation.lastUptimeSeconds,
      lastSubmissionTime: validation.lastSubmissionTime,
      delegationFeeBips: validation.delegationFeeBips
    });
  }

  function getRewardsForEpoch(bytes32 delegationID, uint32 epoch) external view returns (uint256) {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    return $.delegations[delegationID].claimableRewardsPerEpoch[epoch];
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

  function _lockTokens(bytes32 delegationID, uint256[] memory tokenIDs) internal {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    address owner;
    for (uint256 i = 0; i < tokenIDs.length; i++) {
      uint256 tokenID = tokenIDs[i];
      owner = $.licenseContract.ownerOf(tokenID);
      // TODO: Do we need this chekc? or a different call that verifies the owner trying to lock the tokens owns the token
      // we move the burden of chekcing the approval from this function to the caller
      // if (owner != _msgSender()) revert UnauthorizedOwner(owner);
      if ($.tokenLockedBy[tokenID] != bytes32(0)) revert TokenAlreadyLocked(tokenID);
      $.tokenLockedBy[tokenID] = delegationID;
    }
    emit TokensLocked(owner, delegationID, tokenIDs);
  }

  function _lockHardwareToken(bytes32 validationID, uint256 tokenID) internal {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    address owner = $.hardwareLicenseContract.ownerOf(tokenID);
    if (owner != _msgSender()) revert UnauthorizedOwner();
    if ($.hardwareTokenLockedBy[tokenID] != bytes32(0)) revert TokenAlreadyLocked(tokenID);
    $.hardwareTokenLockedBy[tokenID] = validationID;
  }

  function _unlockTokens(bytes32 delegationID, uint256[] memory tokenIDs) internal {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    DelegationInfo storage stake = $.delegations[delegationID];
    address owner = stake.owner;
    for (uint256 i = 0; i < tokenIDs.length; i++) {
      $.tokenLockedBy[tokenIDs[i]] = bytes32(0);
    }
    emit TokensUnlocked(owner, delegationID, tokenIDs);
  }

  function _unlockHardwareToken(uint256 tokenID) internal {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    $.hardwareTokenLockedBy[tokenID] = bytes32(0);
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

  /// @notice Authorizes upgrade to DEFAULT_ADMIN_ROLE
  function _authorizeUpgrade(address newImplementation)
    internal
    override
    onlyRole(DEFAULT_ADMIN_ROLE)
  { }
}
