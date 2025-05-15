// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IERC721 } from "@openzeppelin-contracts-5.3.0/token/ERC721/IERC721.sol";
import { Address } from "@openzeppelin-contracts-5.3.0/utils/Address.sol";

import { EnumerableMap } from "@openzeppelin-contracts-5.3.0/utils/structs/EnumerableMap.sol";
import { EnumerableSet } from "@openzeppelin-contracts-5.3.0/utils/structs/EnumerableSet.sol";

import { AccessControlDefaultAdminRulesUpgradeable } from
  "@openzeppelin-contracts-upgradeable-5.3.0/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import { Initializable } from
  "@openzeppelin-contracts-upgradeable-5.3.0/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from
  "@openzeppelin-contracts-upgradeable-5.3.0/proxy/utils/UUPSUpgradeable.sol";
import { ContextUpgradeable } from
  "@openzeppelin-contracts-upgradeable-5.3.0/utils/ContextUpgradeable.sol";

import {
  PChainOwner,
  Validator,
  ValidatorStatus
} from "icm-contracts-2.0.0/contracts/validator-manager/interfaces/IACP99Manager.sol";
import { ValidatorManager } from
  "icm-contracts-2.0.0/contracts/validator-manager/ValidatorManager.sol";
import { ValidatorMessages } from
  "icm-contracts-2.0.0/contracts/validator-manager/ValidatorMessages.sol";

import { IWarpMessenger, WarpMessage } from "./subnet-evm/IWarpMessenger.sol";
import { NodeLicense } from "./tokens/NodeLicense.sol";

/// @notice Information about each rewards epoch
struct EpochInfo {
  uint256 totalStakedLicenses;
  EnumerableSet.UintSet rewardsMintedFor; // which tokenids have rewards been minted for
}

/// @notice Returnable epoch information
struct EpochInfoView {
  uint256 totalStakedLicenses;
}

/// @notice Validator state information
struct ValidationInfo {
  uint32 startEpoch;
  uint32 endEpoch;
  uint32 licenseCount;
  uint32 lastUptimeSeconds;
  uint32 lastSubmissionTime;
  uint32 delegationFeeBips;
  address owner;
  uint256 hardwareTokenID;
  bytes registrationMessage;
  EnumerableSet.Bytes32Set delegationIDs;
  EnumerableMap.UintToUintMap claimableRewardsPerEpoch;
}

/// @notice Validator information without mappings for view functions
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

/// @notice Delegator statuses
enum DelegatorStatus {
  Unknown,
  PendingAdded,
  Active,
  PendingRemoved
}

/// @notice Delegator information
struct DelegationInfo {
  DelegatorStatus status;
  uint32 startEpoch;
  uint32 endEpoch;
  uint64 startingNonce;
  uint64 endingNonce;
  address owner;
  bytes32 validationID;
  uint256[] tokenIDs;
  EnumerableMap.UintToUintMap claimableRewardsPerEpoch;
  EnumerableSet.UintSet uptimeCheck;
}

/// @notice Delegator information without mappings for view functions
struct DelegationInfoView {
  DelegatorStatus status;
  uint32 startEpoch;
  uint32 endEpoch;
  uint64 startingNonce;
  uint64 endingNonce;
  address owner;
  bytes32 validationID;
  uint256[] tokenIDs;
}

/// @notice Settings for NFT Staking Manager
struct NFTStakingManagerSettings {
  bool bypassUptimeCheck;
  uint16 uptimePercentageBips; // 10000 = 100%
  uint16 maxLicensesPerValidator;
  uint32 initialEpochTimestamp;
  uint32 epochDuration;
  uint32 gracePeriod;
  uint32 minDelegationEpochs;
  uint64 licenseWeight;
  uint64 hardwareLicenseWeight;
  address admin;
  address validatorManager;
  address license;
  address hardwareLicense;
  uint256 epochRewards;
}

/// @notice Interface for minting native tokens on the blockchain
interface INativeMinter {
  function mintNativeCoin(address addr, uint256 amount) external;
}

/// @title NFTStakingManager: Stake NFTs on a blockchain to enable validator registration
///
/// @dev This contract allows a user to stake HardwareOperator NFTs to run validators
///      and delegator NodeLicense NFTs to give the validators weight
///
/// @author MultisigLabs (https://github.com/multisig-labs/validation-managers)
contract NFTStakingManager is
  Initializable,
  UUPSUpgradeable,
  ContextUpgradeable,
  AccessControlDefaultAdminRulesUpgradeable
{
  ///
  /// LIBRARIES
  ///
  using Address for address payable;
  using EnumerableSet for EnumerableSet.UintSet;
  using EnumerableSet for EnumerableSet.Bytes32Set;
  using EnumerableMap for EnumerableMap.AddressToUintMap;
  using EnumerableMap for EnumerableMap.UintToUintMap;

  ///
  /// STORAGE
  ///
  struct NFTStakingManagerStorage {
    bool bypassUptimeCheck;
    uint16 maxLicensesPerValidator;
    uint16 uptimePercentageBips; // 10000 = 100%
    uint32 initialEpochTimestamp;
    uint32 currentTotalStakedLicenses;
    uint32 epochDuration;
    uint32 gracePeriod;
    uint32 minimumDelegationFeeBips; // 0
    uint32 maximumDelegationFeeBips; // 10000
    uint32 minDelegationEpochs;
    uint64 licenseWeight;
    uint64 hardwareLicenseWeight;
    ValidatorManager manager;
    NodeLicense licenseContract;
    IERC721 hardwareLicenseContract;
    uint256 epochRewards;
    // Validation state
    EnumerableSet.Bytes32Set validationIDs;
    mapping(bytes32 validationID => ValidationInfo) validations;
    mapping(uint256 hardwareTokenID => bytes32 validationID) hardwareTokenLockedBy;
    // Delegation state
    mapping(bytes32 delegationID => DelegationInfo) delegations;
    mapping(uint256 nodeLicenseTokenID => bytes32 delegationID) tokenLockedBy;
    mapping(address hardwareOperator => EnumerableMap.AddressToUintMap) prepaidCredits;
    // Epoch state
    mapping(uint32 epochNumber => EpochInfo) epochs;
  }

  NFTStakingManagerStorage private _storage;

  ///
  /// CONSTANTS
  ///
  IWarpMessenger public constant WARP_MESSENGER =
    IWarpMessenger(0x0200000000000000000000000000000000000005);
  INativeMinter public constant NATIVE_MINTER =
    INativeMinter(0x0200000000000000000000000000000000000001);
  // keccak256(abi.encode(uint256(keccak256("gogopool.storage.NFTStakingManagerStorage")) - 1)) & ~bytes32(uint256(0xff));
  bytes32 public constant NFT_STAKING_MANAGER_STORAGE_LOCATION =
    0xb2bea876b5813e5069ed55d22ad257d01245c883a221b987791b00df2f4dfa00;
  bytes32 public constant PREPAYMENT_ROLE = keccak256("PREPAYMENT_ROLE");

  /// @notice Basis points conversion factor used for percentage calculations (100% = 10000 bips)
  uint256 internal constant BIPS_CONVERSION_FACTOR = 10000;

  ///
  /// EVENTS
  ///
  event InitiatedValidatorRegistration(
    bytes32 indexed validationID, uint256 indexed hardwareTokenID, bytes blsPoP
  );
  event CompletedValidatorRegistration(bytes32 indexed validationID, uint32 indexed startEpoch);
  event InitiatedValidatorRemoval(
    bytes32 indexed validationID, uint256 indexed hardwareTokenID, uint32 indexed endEpoch
  );
  event CompletedValidatorRemoval(bytes32 indexed validationID);
  event InitiatedDelegatorRegistration(
    bytes32 indexed validationID, bytes32 indexed delegationID, uint256[] tokenIDs
  );
  event CompletedDelegatorRegistration(
    bytes32 indexed validationID,
    bytes32 indexed delegationID,
    uint32 indexed startEpoch,
    uint64 nonce
  );
  event InitiatedDelegatorRemoval(
    bytes32 indexed validationID,
    bytes32 indexed delegationID,
    uint32 indexed endEpoch,
    uint256[] tokenIDs
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
  error InvalidNonce(uint64 nonce);
  error InsufficientUptime();
  error MaxLicensesPerValidatorReached();
  error MinDelegationDurationNotMet();
  error RewardsAlreadyMintedForTokenID();
  error DelegationDoesNotExist();
  error TokenAlreadyLocked(uint256 tokenID);
  error TokenNotLockedByDelegationID();
  error UnauthorizedOwner();
  error ValidatorHasEnded();
  error ValidatorRegistrationNotComplete();
  error ValidatorHasActiveDelegations();
  error ValidatorNotPoS(bytes32 validationID);
  error ValidatorNotPoA(bytes32 validationID);
  error InvalidDelegationFeeBips(uint32 delegationFeeBips);
  error InvalidDelegatorStatus(DelegatorStatus status);
  error InvalidValidatorStatus(ValidatorStatus status);
  error UnexpectedValidationID(bytes32 expectedValidationID, bytes32 actualValidationID);
  error UptimeAlreadySubmitted();

  /// @notice disable initializers if constructed directly
  constructor() {
    _disableInitializers();
  }

  /// @notice Initializes NFTStakingManager with necessary parameters and settings
  function initialize(NFTStakingManagerSettings calldata settings) external initializer {
    UUPSUpgradeable.__UUPSUpgradeable_init();
    ContextUpgradeable.__Context_init();
    AccessControlDefaultAdminRulesUpgradeable.__AccessControlDefaultAdminRules_init(
      0, settings.admin
    );

    __NFTStakingManager_init(settings);
  }

  /// @notice Chained initializtion function with NFTStakingManager settings
  function __NFTStakingManager_init(NFTStakingManagerSettings calldata settings)
    internal
    onlyInitializing
  {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();

    $.manager = ValidatorManager(settings.validatorManager);
    $.licenseContract = NodeLicense(settings.license);
    $.hardwareLicenseContract = IERC721(settings.hardwareLicense);
    $.initialEpochTimestamp = settings.initialEpochTimestamp;
    $.epochDuration = settings.epochDuration;
    $.licenseWeight = settings.licenseWeight;
    $.hardwareLicenseWeight = settings.hardwareLicenseWeight;
    $.epochRewards = settings.epochRewards;
    $.gracePeriod = settings.gracePeriod;
    $.maxLicensesPerValidator = settings.maxLicensesPerValidator;
    $.uptimePercentageBips = settings.uptimePercentageBips;
    $.bypassUptimeCheck = settings.bypassUptimeCheck;
    $.minimumDelegationFeeBips = 0; // 0%
    $.maximumDelegationFeeBips = 10000; // 100%
    $.minDelegationEpochs = settings.minDelegationEpochs;
  }

  ///
  /// VALIDATOR FUNCTIONS
  ///

  /// @notice Initiate validator registration
  ///
  /// @dev This function takes a HardwareOperatorLicense NFT and calls to the ValidatorManager
  ///      to initiate validator registration.
  ///
  /// @param nodeID Node ID of the validator
  /// @param blsPublicKey BLS public key of the validator
  /// @param blsPoP BLS PoP of the validator
  /// @param remainingBalanceOwner Owner of the remaining balance of the validator
  /// @param disableOwner Owner of the disable address of the validator
  /// @param hardwareTokenID HardwareOperatorLicense NFT token ID
  /// @param delegationFeeBips Delegation fee in bips
  ///
  /// @return validationID created for the valdiator
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

    if (
      delegationFeeBips < $.minimumDelegationFeeBips
        || delegationFeeBips > $.maximumDelegationFeeBips
    ) {
      revert InvalidDelegationFeeBips(delegationFeeBips);
    }

    // will revert if the token does not exist
    $.hardwareLicenseContract.ownerOf(hardwareTokenID);

    bytes32 validationID = $.manager.initiateValidatorRegistration({
      nodeID: nodeID,
      blsPublicKey: blsPublicKey,
      remainingBalanceOwner: remainingBalanceOwner,
      disableOwner: disableOwner,
      weight: $.hardwareLicenseWeight
    });

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
    validation.hardwareTokenID = hardwareTokenID;
    validation.registrationMessage = registerL1ValidatorMessage;
    validation.lastSubmissionTime = getEpochEndTime(getEpochByTimestamp(block.timestamp) - 1);
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

    validation.startEpoch = getEpochByTimestamp(block.timestamp);

    emit CompletedValidatorRegistration(validationID, validation.startEpoch);
    return validationID;
  }

  /// @notice Initiates validator removal
  /// @param validationID The id of validation to remove
  function initiateValidatorRemoval(bytes32 validationID) external {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    ValidationInfo storage validation = $.validations[validationID];
    if (validation.owner != _msgSender()) revert UnauthorizedOwner();

    if (validation.licenseCount > 0) {
      revert ValidatorHasActiveDelegations();
    }

    validation.endEpoch = getEpochByTimestamp(block.timestamp);

    $.manager.initiateValidatorRemoval(validationID);

    emit InitiatedValidatorRemoval(validationID, validation.hardwareTokenID, validation.endEpoch);
  }

  /// @notice Completes validator removal
  ///
  /// @param messageIndex The index of the warp message to complete validator removal
  function completeValidatorRemoval(uint32 messageIndex) external returns (bytes32) {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();

    bytes32 validationID = $.manager.completeValidatorRemoval(messageIndex);

    ValidationInfo storage validation = $.validations[validationID];

    _unlockHardwareToken(validation.hardwareTokenID);

    emit CompletedValidatorRemoval(validationID);

    return validationID;
  }

  /// @notice callable by the delagtor to stake node licenses
  ///
  /// @param validationID the validation id of the validator
  /// @param tokenIDs the token ids of the licenses to stake
  ///
  /// @return the delegation id
  function initiateDelegatorRegistration(bytes32 validationID, uint256[] calldata tokenIDs)
    public
    returns (bytes32)
  {
    return _initiateDelegatorRegistration(validationID, _msgSender(), tokenIDs);
  }

  /// @notice callable by the validation owner to stake node licenses on behalf of the delagtor
  ///
  /// @param validationID the validation id of the validator
  /// @param owner the owner of the licenses
  /// @param tokenIDs the token ids of the licenses to stake
  ///
  /// @return the delegation id
  function initiateDelegatorRegistrationOnBehalfOf(
    bytes32 validationID,
    address owner,
    uint256[] calldata tokenIDs
  ) public returns (bytes32) {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();

    bool isApprovedForAll = $.licenseContract.isDelegationApprovedForAll(owner, _msgSender());

    // If no blanket approval, check each token individually
    if (!isApprovedForAll) {
      for (uint256 i = 0; i < tokenIDs.length; i++) {
        if ($.licenseContract.getDelegationApproval(tokenIDs[i]) != _msgSender()) {
          revert UnauthorizedOwner();
        }
      }
    }

    return _initiateDelegatorRegistration(validationID, owner, tokenIDs);
  }

  /// @notice internal function to initiate a delegation
  ///
  /// @param validationID the validation id of the validator
  /// @param owner the owner of the licenses
  /// @param tokenIDs the token ids of the licenses to stake
  ///
  /// @return the delegation id
  function _initiateDelegatorRegistration(
    bytes32 validationID,
    address owner,
    uint256[] calldata tokenIDs
  ) internal returns (bytes32) {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    ValidationInfo storage validation = $.validations[validationID];

    for (uint256 i = 0; i < tokenIDs.length; i++) {
      if ($.licenseContract.ownerOf(tokenIDs[i]) != owner) {
        revert UnauthorizedOwner();
      }
    }

    if (validation.owner == address(0)) {
      revert ValidatorNotPoS(validationID);
    }

    if (validation.endEpoch != 0) {
      revert ValidatorHasEnded();
    }

    if (validation.startEpoch == 0 || validation.startEpoch > getEpochByTimestamp(block.timestamp))
    {
      revert ValidatorRegistrationNotComplete();
    }

    // Update license count
    validation.licenseCount += uint32(tokenIDs.length);
    if (validation.licenseCount > $.maxLicensesPerValidator) {
      revert MaxLicensesPerValidatorReached();
    }

    // Update validator weight
    Validator memory validator = $.manager.getValidator(validationID);
    uint64 newWeight = validator.weight + $.licenseWeight * uint64(tokenIDs.length);
    (uint64 nonce,) = $.manager.initiateValidatorWeightUpdate(validationID, newWeight);

    bytes32 delegationID = keccak256(abi.encodePacked(validationID, nonce));

    validation.delegationIDs.add(delegationID);

    _lockTokens(delegationID, tokenIDs);

    DelegationInfo storage newDelegation = $.delegations[delegationID];
    newDelegation.owner = owner;
    newDelegation.tokenIDs = tokenIDs;
    newDelegation.status = DelegatorStatus.PendingAdded;
    newDelegation.validationID = validationID;
    newDelegation.startingNonce = nonce;

    emit InitiatedDelegatorRegistration(validationID, delegationID, tokenIDs);
    return delegationID;
  }

  /// @notice Completes a delegator registration
  ///
  /// @dev This function takes a delegationID because we can't get the delegation from
  ///      the warp message itself
  ///
  /// @param delegationID the id of the delegation to complete
  /// @param messageIndex the index of the warp message to complete the delegation
  function completeDelegatorRegistration(bytes32 delegationID, uint32 messageIndex) public {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();

    DelegationInfo storage delegation = $.delegations[delegationID];

    if (delegation.status != DelegatorStatus.PendingAdded) {
      revert InvalidDelegatorStatus(delegation.status);
    }

    Validator memory validator = $.manager.getValidator(delegation.validationID);
    if (validator.status != ValidatorStatus.Active) {
      revert InvalidValidatorStatus(validator.status);
    }

    uint64 nonce;

    if (validator.receivedNonce < delegation.startingNonce) {
      (bytes32 validationID, uint64 receivedNonce) =
        $.manager.completeValidatorWeightUpdate(messageIndex);
      nonce = receivedNonce;

      if (validationID != delegation.validationID) {
        revert UnexpectedValidationID(delegation.validationID, validationID);
      }

      if (nonce < delegation.startingNonce) {
        revert InvalidNonce(nonce);
      }
    }

    delegation.status = DelegatorStatus.Active;
    delegation.startEpoch = getEpochByTimestamp(block.timestamp);

    emit CompletedDelegatorRegistration(
      delegation.validationID, delegationID, delegation.startEpoch, nonce
    );
  }

  /// @notice Initiates removal of one or more delegations
  ///
  /// @param delegationIDs The ids of the delegations to remove
  function initiateDelegatorRemoval(bytes32[] calldata delegationIDs) public {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();

    for (uint256 i = 0; i < delegationIDs.length; i++) {
      DelegationInfo storage delegation = $.delegations[delegationIDs[i]];
      ValidationInfo storage validation = $.validations[delegation.validationID];
      Validator memory validator = $.manager.getValidator(delegation.validationID);

      if (
        delegation.owner == _msgSender()
          && delegation.startEpoch + $.minDelegationEpochs > getEpochByTimestamp(block.timestamp)
      ) {
        revert MinDelegationDurationNotMet();
      }

      if (delegation.owner != _msgSender() && validation.owner != _msgSender()) {
        revert UnauthorizedOwner();
      }

      if (delegation.status != DelegatorStatus.Active) {
        revert InvalidDelegatorStatus(delegation.status);
      }

      uint64 newWeight = validator.weight - $.licenseWeight * uint64(delegation.tokenIDs.length);

      (uint64 nonce,) = $.manager.initiateValidatorWeightUpdate(delegation.validationID, newWeight);

      delegation.endEpoch = getEpochByTimestamp(block.timestamp) - 1;
      delegation.endingNonce = nonce;
      delegation.status = DelegatorStatus.PendingRemoved;

      validation.licenseCount -= uint32(delegation.tokenIDs.length);
      validation.delegationIDs.remove(delegationIDs[i]);

      emit InitiatedDelegatorRemoval(
        delegation.validationID, delegationIDs[i], delegation.endEpoch, delegation.tokenIDs
      );
    }
  }

  /// @notice Completes delegator removal
  ///
  /// @param delegationID The id of the delegation to complete
  /// @param messageIndex The index of the warp message to complete the delegation
  ///
  /// @return validationID The id of the validation that was updated
  function completeDelegatorRemoval(bytes32 delegationID, uint32 messageIndex)
    external
    returns (bytes32)
  {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();

    DelegationInfo storage delegation = $.delegations[delegationID];
    if (delegation.status != DelegatorStatus.PendingRemoved) {
      revert InvalidDelegatorStatus(delegation.status);
    }

    Validator memory validator = $.manager.getValidator(delegation.validationID);
    bytes32 validationID = delegation.validationID;
    uint64 nonce;

    if (
      validator.status != ValidatorStatus.Completed
        && validator.receivedNonce < delegation.endingNonce
    ) {
      (bytes32 receivedValidationID, uint64 receivedNonce) =
        $.manager.completeValidatorWeightUpdate(messageIndex);
      nonce = receivedNonce;

      if (receivedValidationID != validationID) {
        revert UnexpectedValidationID(receivedValidationID, validationID);
      }

      // The received nonce should be at least as high as the delegation's ending nonce. This allows a weight
      // update using a higher nonce (which implicitly includes the delegation's weight update) to be used to
      // complete delisting for an earlier delegation. This is necessary because the P-Chain is only willing
      // to sign the latest weight update.
      if (delegation.endingNonce > nonce) {
        revert InvalidNonce(nonce);
      }
    }

    // we never delete the delegation so that the user can claim rewards whenever
    _unlockTokens(delegationID, delegation.tokenIDs);
    emit CompletedDelegatorRemoval(validationID, delegationID, nonce);
    return delegationID;
  }

  /// @notice Hardware operator can add prepaid credits for a license holder
  ///
  /// @param licenseHolder The address of the license holder
  /// @param creditSeconds The number of credit seconds to add
  function addPrepaidCredits(address hardwareOperator, address licenseHolder, uint32 creditSeconds)
    external
    onlyRole(PREPAYMENT_ROLE)
  {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    (, uint256 currentCredits) = $.prepaidCredits[hardwareOperator].tryGet(licenseHolder);
    $.prepaidCredits[hardwareOperator].set(licenseHolder, currentCredits + creditSeconds);
    emit PrepaidCreditsAdded(hardwareOperator, licenseHolder, creditSeconds);
  }

  /// @notice Processes a proof of an uptime message for a validator
  ///
  /// @dev We are tracking uptime per epoch, so we record uptime and submission time for pervious
  ///      epochs and check that the uptime is sufficient for the current epoch.
  ///
  /// @param messageIndex The index of the warp message that contains the proof
  function processProof(uint32 messageIndex) public {
    (bytes32 validationID, uint64 uptimeSeconds) =
      ValidatorMessages.unpackValidationUptimeMessage(_getPChainWarpMessage(messageIndex).payload);

    uint32 currentEpoch = getEpochByTimestamp(uint32(block.timestamp));
    uint32 previousEpoch = currentEpoch - 1;
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    if (previousEpoch == 0 || block.timestamp < getEpochEndTime(previousEpoch)) {
      revert EpochHasNotEnded();
    }

    if (block.timestamp >= getEpochEndTime(previousEpoch) + $.gracePeriod) {
      revert GracePeriodHasPassed();
    }

    ValidationInfo storage validation = $.validations[validationID];

    if (getEpochByTimestamp(validation.lastSubmissionTime) == currentEpoch) {
      revert UptimeAlreadySubmitted();
    }

    if (!$.bypassUptimeCheck) {
      uint32 lastSubmissionTime = validation.lastSubmissionTime;
      uint32 lastUptimeSeconds = validation.lastUptimeSeconds;

      uint32 uptimeDelta = uint32(uptimeSeconds) - lastUptimeSeconds;
      uint32 submissionTimeDelta = uint32(block.timestamp) - lastSubmissionTime;
      uint256 effectiveUptime = uint256(uptimeDelta) * $.epochDuration / submissionTimeDelta;

      validation.lastUptimeSeconds = uint32(uptimeSeconds);
      validation.lastSubmissionTime = uint32(block.timestamp);

      if (effectiveUptime < _expectedUptime()) {
        return;
      }
    }

    EpochInfo storage epochInfo = $.epochs[previousEpoch];
    epochInfo.totalStakedLicenses += validation.licenseCount;

    // then for each delegation that was on the active validator, record that they can get rewards
    for (uint256 i = 0; i < validation.delegationIDs.length(); i++) {
      bytes32 delegationID = validation.delegationIDs.at(i);
      DelegationInfo storage delegation = $.delegations[delegationID];
      delegation.uptimeCheck.add(previousEpoch);
    }
  }

  /// @notice Mints rewards for a validator
  ///
  /// @param validationIDs The ids of the validators to mint rewards for
  /// @param epoch The epoch to mint rewards for
  function mintRewards(bytes32[] calldata validationIDs, uint32 epoch) external {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();

    if (block.timestamp <= getEpochEndTime(epoch) + $.gracePeriod) {
      revert GracePeriodHasNotPassed();
    }

    uint256 rewardsToMint = 0;
    for (uint256 i = 0; i < validationIDs.length; i++) {
      ValidationInfo storage validation = $.validations[validationIDs[i]];
      uint256 totalDelegations = validation.delegationIDs.length();

      for (uint256 j = 0; j < totalDelegations; j++) {
        bytes32 delegationID = validation.delegationIDs.at(j);
        DelegationInfo storage delegation = $.delegations[delegationID];
        if (delegation.uptimeCheck.contains(epoch) && epoch >= delegation.startEpoch) {
          rewardsToMint += _mintRewardsPerDelegator(epoch, delegationID);
        }
      }
    }

    NATIVE_MINTER.mintNativeCoin(address(this), rewardsToMint);
  }

  /// @notice Calculates rewards to mint per delegator of a validation
  ///
  /// @param epoch Epoch to mint rewards for
  /// @param delegationID ID of delegation to compute rewards for
  ///
  /// @return rewardsToMint the amount of rewards to mint for the delegation
  function _mintRewardsPerDelegator(uint32 epoch, bytes32 delegationID)
    internal
    returns (uint256 rewardsToMint)
  {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    DelegationInfo storage delegation = $.delegations[delegationID];
    ValidationInfo storage validation = $.validations[delegation.validationID];
    EpochInfo storage epochInfo = $.epochs[epoch];

    if (delegation.owner == address(0)) {
      revert DelegationDoesNotExist();
    }

    if (epoch < delegation.startEpoch || (epoch > delegation.endEpoch && delegation.endEpoch != 0))
    {
      revert EpochOutOfRange();
    }

    for (uint256 i = 0; i < delegation.tokenIDs.length; i++) {
      if ($.tokenLockedBy[delegation.tokenIDs[i]] != delegationID) {
        revert TokenNotLockedByDelegationID();
      }
      if (epochInfo.rewardsMintedFor.contains(delegation.tokenIDs[i])) {
        revert RewardsAlreadyMintedForTokenID();
      }

      epochInfo.rewardsMintedFor.add(delegation.tokenIDs[i]);
    }

    // If the license holder has prepaid credits, deduct them.
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

    (, uint256 claimableRewards) = validation.claimableRewardsPerEpoch.tryGet(uint256(epoch));
    validation.claimableRewardsPerEpoch.set(uint256(epoch), claimableRewards + delegationFee);

    delegation.claimableRewardsPerEpoch.set(uint256(epoch), totalRewards - delegationFee);

    emit RewardsMinted(epoch, delegationID, totalRewards);

    return totalRewards;
  }

  /// @notice Logic to claim rewards for a validator or delegator
  ///
  /// @param owner The owner of the validator or delegator
  /// @param rewardsMap The map of rewards to claim
  /// @param id The id of the validator or delegator
  /// @param maxEpochs The maximum number of epochs to claim rewards for
  ///
  /// @return totalRewards The total rewards to claim
  function _claimRewards(
    address owner,
    EnumerableMap.UintToUintMap storage rewardsMap,
    bytes32 id,
    uint32 maxEpochs
  ) internal returns (uint256, uint32[] memory) {
    if (maxEpochs > rewardsMap.length()) {
      maxEpochs = uint32(rewardsMap.length());
    }

    uint256 totalRewards = 0;
    uint32[] memory claimedEpochNumbers = new uint32[](maxEpochs);
    uint256[] memory rewardsAmounts = new uint256[](maxEpochs);

    for (uint32 i = 0; i < maxEpochs; i++) {
      (uint256 epochNumber, uint256 rewards) = rewardsMap.at(0);
      // State changes
      claimedEpochNumbers[i] = uint32(epochNumber);
      totalRewards += rewards;
      rewardsAmounts[i] = rewards;
      // this remove updates the array indicies. so always remove item 0
      rewardsMap.remove(epochNumber);
    }

    // Events (after all state changes)
    for (uint32 i = 0; i < maxEpochs; i++) {
      emit RewardsClaimed(claimedEpochNumbers[i], id, rewardsAmounts[i]);
    }

    payable(owner).sendValue(totalRewards);
    return (totalRewards, claimedEpochNumbers);
  }

  /// @notice Claims rewards for a delegation
  ///
  /// @param delegationID The id of the delegation to claim
  /// @param maxEpochs The maximum number of epochs to claim
  ///
  /// @return totalRewards The total rewards to claim
  function claimRewards(bytes32 delegationID, uint32 maxEpochs)
    external
    returns (uint256, uint32[] memory)
  {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    DelegationInfo storage delegation = $.delegations[delegationID];

    if (delegation.owner != _msgSender()) revert UnauthorizedOwner();

    return
      _claimRewards(delegation.owner, delegation.claimableRewardsPerEpoch, delegationID, maxEpochs);
  }

  /// @notice Claims rewards for a validator
  ///
  /// @param validationID The id of the validator to claim rewards for
  /// @param maxEpochs The maximum number of epochs to claim
  ///
  /// @return totalRewards The total rewards to claim
  function claimValidatorRewards(bytes32 validationID, uint32 maxEpochs)
    external
    returns (uint256, uint32[] memory)
  {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    ValidationInfo storage validation = $.validations[validationID];
    if (validation.owner != _msgSender()) revert UnauthorizedOwner();

    return
      _claimRewards(validation.owner, validation.claimableRewardsPerEpoch, validationID, maxEpochs);
  }

  ///
  /// ADMIN FUNCTIONS
  ///
  /// @notice Gets the current settings for the NFT Staking Manager
  ///
  /// @return settings The current settings for the NFT Staking Manager
  function getSettings() external view returns (NFTStakingManagerSettings memory) {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    NFTStakingManagerSettings memory settings = NFTStakingManagerSettings({
      bypassUptimeCheck: $.bypassUptimeCheck,
      uptimePercentageBips: $.uptimePercentageBips,
      maxLicensesPerValidator: $.maxLicensesPerValidator,
      initialEpochTimestamp: $.initialEpochTimestamp,
      epochDuration: $.epochDuration,
      gracePeriod: $.gracePeriod,
      minDelegationEpochs: $.minDelegationEpochs,
      licenseWeight: $.licenseWeight,
      hardwareLicenseWeight: $.hardwareLicenseWeight,
      validatorManager: address($.manager),
      license: address($.licenseContract),
      hardwareLicense: address($.hardwareLicenseContract),
      epochRewards: $.epochRewards,
      admin: defaultAdmin()
    });
    return settings;
  }

  /// @notice Sets the bypass uptime check flag
  ///
  /// @param bypass The new bypass uptime check flag
  function setBypassUptimeCheck(bool bypass) external onlyRole(DEFAULT_ADMIN_ROLE) {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    $.bypassUptimeCheck = bypass;
  }

  /// @notice Calculates the rewards per license for an epoch
  ///
  /// @param epochNumber The epoch to calculate rewards for
  ///
  /// @return rewardsPerLicense The rewards per license for the epoch
  function calculateRewardsPerLicense(uint32 epochNumber) public view returns (uint256) {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    return $.epochRewards / $.epochs[epochNumber].totalStakedLicenses;
  }

  /// @notice Gets the epoch number for a given timestamp
  ///
  /// @param timestamp The timestamp to get the epoch number for
  ///
  /// @return epochNumber The epoch number for the given timestamp
  function getEpochByTimestamp(uint256 timestamp) public view returns (uint32) {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    // we don't want to have a 0 epoch, because 0 is also a falsy value
    uint32 epoch = (uint32(timestamp) - $.initialEpochTimestamp) / $.epochDuration;
    return epoch + 1;
  }

  /// @notice Gets the end time of an epoch
  ///
  /// @param epoch The epoch to get the end time for
  ///
  /// @return endTime The end time of the epoch
  function getEpochEndTime(uint32 epoch) public view returns (uint32) {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    return $.initialEpochTimestamp + (epoch * $.epochDuration);
  }

  /// @notice Gets the epoch info for a given epoch
  ///
  /// @param epoch The epoch to get the info for
  ///
  /// @return epochInfo The info for the epoch
  function getEpochInfoView(uint32 epoch) external view returns (EpochInfoView memory) {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    return EpochInfoView({ totalStakedLicenses: $.epochs[epoch].totalStakedLicenses });
  }

  /// @notice Gets the token locked by for a given token ID
  ///
  /// @param tokenID The token ID to get the locked by for
  ///
  /// @return lockedBy The address that the token is locked by
  function getTokenLockedBy(uint256 tokenID) external view returns (bytes32) {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    return $.tokenLockedBy[tokenID];
  }

  /// @notice Gets the hardware token locked by for a given token ID
  ///
  /// @param tokenID The token ID to get the locked by for
  ///
  /// @return lockedBy The address that the token is locked by
  function getHardwareTokenLockedBy(uint256 tokenID) external view returns (bytes32) {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    return $.hardwareTokenLockedBy[tokenID];
  }

  /// @notice Gets the validation IDs
  ///
  /// @return validationIDs The validation IDs
  function getValidationIDs() external view returns (bytes32[] memory) {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    return $.validationIDs.values();
  }

  /// @notice Gets the prepaid credits for a hardware operator and license holder
  ///
  /// @param hardwareOperator The hardware operator to get the prepaid credits for
  /// @param licenseHolder The license holder to get the prepaid credits for
  ///
  /// @return creditSeconds The prepaid credits for the hardware operator and license holder
  function getPrepaidCredits(address hardwareOperator, address licenseHolder)
    external
    view
    returns (uint256)
  {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    (bool success, uint256 creditSeconds) = $.prepaidCredits[hardwareOperator].tryGet(licenseHolder);
    if (!success) {
      return 0;
    }
    return creditSeconds;
  }

  /// @notice Gets the delegations for a validation
  ///
  /// @param validationID The id of the validation to get the delegations for
  ///
  /// @return delegationIDs The delegations for the validation
  function getDelegations(bytes32 validationID) external view returns (bytes32[] memory) {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    ValidationInfo storage validation = $.validations[validationID];
    return validation.delegationIDs.values();
  }

  /// @notice Gets the delegation info for a delegation
  ///
  /// @param delegationID The id of the delegation to get the info for
  ///
  /// @return delegationInfo The info for the delegation
  function getDelegationInfoView(bytes32 delegationID)
    external
    view
    returns (DelegationInfoView memory)
  {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    DelegationInfo storage delegation = $.delegations[delegationID];
    return DelegationInfoView({
      status: delegation.status,
      owner: delegation.owner,
      validationID: delegation.validationID,
      startEpoch: delegation.startEpoch,
      endEpoch: delegation.endEpoch,
      startingNonce: delegation.startingNonce,
      endingNonce: delegation.endingNonce,
      tokenIDs: delegation.tokenIDs
    });
  }

  /// @notice Gets the validation info for a validation
  ///
  /// @param validationID The id of the validation to get the info for
  ///
  /// @return validationInfo The info for the validation
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

  /// @notice Gets the rewards for a delegation for a given epoch
  ///
  /// @param delegationID The id of the delegation to get the rewards for
  /// @param epoch The epoch to get the rewards for
  ///
  /// @return rewards The rewards for the delegation for the given epoch
  function getRewardsForEpoch(bytes32 delegationID, uint32 epoch) external view returns (uint256) {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    (bool success, uint256 rewards) =
      $.delegations[delegationID].claimableRewardsPerEpoch.tryGet(uint256(epoch));
    if (!success) {
      return 0;
    }
    return rewards;
  }

  /// @notice Gets the key for a given epoch and token ID
  ///
  /// @param epochNumber The epoch number
  /// @param tokenID The token ID
  ///
  /// @return key The key for the given epoch and token ID
  function _getKey(uint32 epochNumber, uint256 tokenID) internal pure returns (bytes32) {
    return keccak256(abi.encode(epochNumber, tokenID));
  }

  /// @notice Gets the expected uptime for a given epoch
  ///
  /// @return uptime The expected uptime for the given epoch
  function _expectedUptime() internal view returns (uint256) {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    return $.epochDuration * $.uptimePercentageBips / BIPS_CONVERSION_FACTOR;
  }

  /// @notice Gets the NFT Staking Manager storage
  ///
  /// @return $ The NFT Staking Manager storage
  function _getNFTStakingManagerStorage() private pure returns (NFTStakingManagerStorage storage $) {
    // solhint-disable-next-line no-inline-assembly
    assembly {
      $.slot := NFT_STAKING_MANAGER_STORAGE_LOCATION
    }
  }

  /// @notice Locks tokens for a delegation
  ///
  /// @param delegationID The id of the delegation to lock the tokens for
  /// @param tokenIDs The token IDs to lock
  function _lockTokens(bytes32 delegationID, uint256[] memory tokenIDs) internal {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    address owner;
    for (uint256 i = 0; i < tokenIDs.length; i++) {
      uint256 tokenID = tokenIDs[i];
      owner = $.licenseContract.ownerOf(tokenID);
      if ($.tokenLockedBy[tokenID] != bytes32(0)) revert TokenAlreadyLocked(tokenID);
      $.tokenLockedBy[tokenID] = delegationID;
    }
    emit TokensLocked(owner, delegationID, tokenIDs);
  }

  /// @notice Locks a hardware token
  ///
  /// @param validationID The id of the validation to lock the hardware token for
  /// @param tokenID The token ID to lock
  function _lockHardwareToken(bytes32 validationID, uint256 tokenID) internal {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    address owner = $.hardwareLicenseContract.ownerOf(tokenID);
    if (owner != _msgSender()) revert UnauthorizedOwner();
    if ($.hardwareTokenLockedBy[tokenID] != bytes32(0)) revert TokenAlreadyLocked(tokenID);
    $.hardwareTokenLockedBy[tokenID] = validationID;
  }

  /// @notice Unlocks tokens for a delegation
  ///
  /// @param delegationID The id of the delegation to unlock the tokens for
  /// @param tokenIDs The token IDs to unlock
  function _unlockTokens(bytes32 delegationID, uint256[] memory tokenIDs) internal {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    DelegationInfo storage stake = $.delegations[delegationID];
    address owner = stake.owner;
    for (uint256 i = 0; i < tokenIDs.length; i++) {
      $.tokenLockedBy[tokenIDs[i]] = bytes32(0);
    }
    emit TokensUnlocked(owner, delegationID, tokenIDs);
  }

  /// @notice Unlocks a hardware token
  ///
  /// @param tokenID The token ID to unlock
  function _unlockHardwareToken(uint256 tokenID) internal {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    $.hardwareTokenLockedBy[tokenID] = bytes32(0);
  }

  /// @notice Gets a P-Chain warp message
  ///
  /// @param messageIndex The index of the warp message to get
  ///
  /// @return warpMessage The warp message
  function _getPChainWarpMessage(uint32 messageIndex) internal view returns (WarpMessage memory) {
    (WarpMessage memory warpMessage, bool valid) =
      WARP_MESSENGER.getVerifiedWarpMessage(messageIndex);
    if (!valid) {
      revert InvalidWarpMessage();
    }
    // Must match to P-Chain blockchain id, which is 0.
    if (warpMessage.sourceChainID != bytes32(0)) {
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
