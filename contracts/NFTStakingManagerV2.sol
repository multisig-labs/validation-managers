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
  uint40 lastUptimeSeconds;
  uint40 lastSubmissionTime;
  uint32 delegationFeeBips;
  bytes registrationMessage;
  EnumerableSet.Bytes32Set delegationIds;
  mapping(uint32 epochNumber => uint256 rewards) claimableRewardsPerEpoch; // will get set to zero when claimed
}

struct ValidationInfoView {
  address owner;
  uint256 hardwareTokenId;
  uint32 startEpoch;
  uint32 endEpoch;
  uint32 licenseCount;
  bytes registrationMessage;
  uint40 lastUptimeSeconds;
  uint40 lastSubmissionTime;
  uint32 delegationFeeBips;
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
  address admin;
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
  uint256 uptimePercentage; // 100 = 100%
}

contract NFTStakingManager is
  Initializable,
  UUPSUpgradeable,
  ContextUpgradeable,
  AccessControlUpgradeable,
  ReentrancyGuardUpgradeable
{
  using Address for address payable;
  using EnumerableSet for EnumerableSet.UintSet;
  using EnumerableSet for EnumerableSet.Bytes32Set;
  using EnumerableMap for EnumerableMap.AddressToUintMap;

  /// @notice Basis points conversion factor used for percentage calculations (100% = 10000 bips)
  uint256 internal constant BIPS_CONVERSION_FACTOR = 10000;

  error TokenAlreadyLocked(uint256 tokenId);
  error UnauthorizedOwner(address owner);
  error EpochOutOfRange(uint32 currentEpoch, uint32 startEpoch, uint32 endEpoch);
  error InsufficientUptime();
  error ZeroAddress();

  event DelegationRegistrationInitiated(
    bytes32 indexed validationId, bytes32 indexed delegationId, uint256[] tokenIds
  );
  event DelegationRegistrationCompleted(
    bytes32 indexed validationId, bytes32 indexed delegationId, uint32 startEpoch
  );
  event TokensLocked(address indexed owner, bytes32 indexed stakeId, uint256[] tokenIds);
  event TokensUnlocked(address indexed owner, bytes32 indexed stakeId, uint256[] tokenIds);
  event RewardsMinted(uint32 indexed epochNumber, bytes32 indexed stakeId, uint256 rewards);
  event RewardsClaimed(uint32 indexed epochNumber, bytes32 indexed stakeId, uint256 rewards);
  event PrepaidCreditsAdded(
    address indexed hardwareOperator, address indexed licenseHolder, uint32 creditSeconds
  );

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
    uint256 uptimePercentage; // 100 = 100%
    uint32 gracePeriod; // starting at 1 hours
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
  }

  function initiateDelegatorRegistration(bytes32 validationId, uint256[] calldata tokenIds)
    public
    returns (bytes32)
  {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    ValidationInfo storage validation = $.validations[validationId];
    if (validation.endEpoch != 0) {
      revert("Validator has ended");
    }
    if (validation.startEpoch == 0 || validation.startEpoch > getCurrentEpoch()) {
      revert("Validator registration not complete");
    }
    validation.licenseCount += uint32(tokenIds.length);
    if (validation.licenseCount > $.maxLicensesPerValidator) {
      revert("Max licenses per validator reached");
    }

    Validator memory validator = $.manager.getValidator(validationId);
    uint64 newWeight = validator.weight + _getWeight(tokenIds.length);
    (uint64 nonce,) = $.manager.initiateValidatorWeightUpdate(validationId, newWeight);

    bytes32 delegationId = keccak256(abi.encodePacked(validationId, nonce));

    validation.delegationIds.add(delegationId);

    _lockTokens(delegationId, tokenIds);

    DelegationInfo storage newDelegation = $.delegations[delegationId];
    newDelegation.owner = _msgSender();
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
      revert("Validation ID mismatch");
    }
    ValidationInfo storage validation = $.validations[validationId];
    validation.licenseCount += uint32(delegation.tokenIds.length);

    delegation.startEpoch = getCurrentEpoch();
    emit DelegationRegistrationCompleted(validationId, delegationId, delegation.startEpoch);
  }

  // TODO enforce a min duration?
  function initiateDelegatorRemoval(bytes32 delegationId) external {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();

    DelegationInfo storage delegation = $.delegations[delegationId];
    ValidationInfo storage validation = $.validations[delegation.validationId];
    Validator memory validator = $.manager.getValidator(delegation.validationId);

    if (delegation.owner != _msgSender()) revert UnauthorizedOwner(_msgSender());

    // TODO figure out which vars to update now and which after the weight update

    // End the delegation as of the prev epoch, so users will not receive rewards for the current epoch
    // as they were not present for the whole epoch duration
    delegation.endEpoch = getCurrentEpoch() - 1;
    validation.licenseCount -= uint32(delegation.tokenIds.length);
    uint64 newWeight = validator.weight - _getWeight(delegation.tokenIds.length);
    // Do not delete delegation yet, we need it to pay out rewards in the case that a delegator leaves
    // during the grace period when proofs are being submitted
    // validation.delegationIds.remove(delegationId);

    (uint64 nonce,) = $.manager.initiateValidatorWeightUpdate(delegation.validationId, newWeight);
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
    validation.lastSubmissionTime = getEpochStartTime(getCurrentEpoch());
    validation.delegationFeeBips = delegationFeeBips;

    // The blsPoP is required to complete the validator registration on the P-Chain, so store it here
    // for an off-chain service to use to complete the registration.
    bytes20 fixedNodeID = _fixedNodeID(nodeID);
    $.nodes[fixedNodeID] =
      NodeInfo({ owner: _msgSender(), blsPublicKey: blsPublicKey, blsPoP: blsPoP });

    return validationId;
  }

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
    if (validation.owner != _msgSender()) revert UnauthorizedOwner(_msgSender());
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

  // Anyone can call mintRewards functions to mint rewards (prob backend cron process)
  // No special permissions necessary. In future this could accept uptime proof as well.
  // after verifiying the total amount
  function mintRewards(bytes32[] calldata validationIds) external {
    for (uint256 i = 0; i < validationIds.length; i++) {
      mintRewards(validationIds[i]);
    }
  }

  function processProof(bytes32 validationId, uint256 uptimeSeconds) public {
    // TODO: retrieve the uptime proof
    // (bytes32 validationID, uint64 uptime) = ValidatorMessages.unpackValidationUptimeMessage(
    //   _getPChainWarpMessage(messageIndex, uptimeBlockchainID).payload
    // );

    uint32 epoch = getEpochByTimestamp(uint32(block.timestamp));
    epoch--;
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    if (epoch == 0) {
      revert("Epoch has not ended");
    }

    if (_hasGracePeriodPassed(epoch)) {
      revert("Grace period has passed");
    }

    ValidationInfo storage validation = $.validations[validationId];

    // TODO just init these values when the validator is registered

    uint40 lastSubmissionTime = validation.lastSubmissionTime;
    uint40 lastUptimeSeconds = validation.lastUptimeSeconds;
    uint40 uptimeDelta = uint40(uptimeSeconds) - lastUptimeSeconds;
    uint40 submissionTimeDelta = uint40(block.timestamp) - lastSubmissionTime;
    console2.log("UPTIME DELTA", uptimeDelta);
    console2.log("SUBMISSION TIME DELTA", submissionTimeDelta);
    uint256 effectiveUptime = uptimeDelta * $.epochDuration / submissionTimeDelta;

    console2.log("EFFECTIVE UPTIME", effectiveUptime);
    console2.log("EXPECTED UPTIME", _expectedUptime());
    if (effectiveUptime < _expectedUptime()) {
      revert InsufficientUptime();
    }

    // Only update state if uptime check passes
    validation.lastUptimeSeconds = uint40(uptimeSeconds);
    validation.lastSubmissionTime = uint40(block.timestamp);

    EpochInfo storage epochInfo = $.epochs[epoch];

    // then for each delegation that was on the active validator, record that they can get rewards
    for (uint256 i = 0; i < validation.delegationIds.length(); i++) {
      bytes32 delegationId = validation.delegationIds.at(i);
      DelegationInfo storage delegation = $.delegations[delegationId];
      delegation.uptimeCheck[epoch] = true;
      epochInfo.totalStakedLicenses += delegation.tokenIds.length;
    }
  }

  function mintRewards(bytes32 validationId) public {
    uint32 epoch = getEpochByTimestamp(uint32(block.timestamp));
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
      revert("Stake does not exist");
    }

    if (epoch < delegation.startEpoch || (epoch > delegation.endEpoch && delegation.endEpoch != 0))
    {
      revert EpochOutOfRange(epoch, delegation.startEpoch, delegation.endEpoch);
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
        revert("Token not locked by this stakeId");
      }
      if ($.isRewardsMinted[epoch][delegation.tokenIds[i]]) {
        revert("Rewards already minted for this tokenId");
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

  function claimRewards(address owner) external { }

  function claimRewards(bytes32 delegationId, uint32 maxEpochs)
    external
    returns (uint256, uint32[] memory)
  {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    DelegationInfo storage delegation = $.delegations[delegationId];

    if (delegation.owner != _msgSender()) revert UnauthorizedOwner(_msgSender());
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
    return $.initialEpochTimestamp + (epoch * $.epochDuration);
  }

  function getEpochStartTime(uint32 epoch) public view returns (uint40) {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    return $.initialEpochTimestamp + (epoch - 1) * $.epochDuration;
  }

  function getEpochInfo(uint32 epoch) external view returns (EpochInfo memory) {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    return $.epochs[epoch];
  }

  function _expectedUptime() public view returns (uint256) {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    return $.epochDuration * $.uptimePercentage / 100;
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
      if (owner != _msgSender()) revert UnauthorizedOwner(owner);
      if ($.tokenLockedBy[tokenId] != bytes32(0)) revert TokenAlreadyLocked(tokenId);
      $.tokenLockedBy[tokenId] = stakeId;
    }
    emit TokensLocked(owner, stakeId, tokenIds);
  }

  function _lockHardwareToken(bytes32 stakeId, uint256 tokenId) internal {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    address owner = $.hardwareLicenseContract.ownerOf(tokenId);
    if (owner != _msgSender()) revert UnauthorizedOwner(owner);
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
