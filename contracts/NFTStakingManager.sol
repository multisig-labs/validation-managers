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

interface INativeMinter {
  function mintNativeCoin(address addr, uint256 amount) external;
}

struct EpochInfo {
  uint256 totalStakedLicenses;
}

struct StakeInfo {
  address owner;
  uint32 startEpoch;
  uint32 endEpoch;
  uint256[] tokenIds;
  mapping(uint32 epochNumber => uint256 rewards) claimableRewardsPerEpoch; // will get set to zero when claimed
  EnumerableSet.UintSet claimableEpochNumbers;
}

// Without nested mappings, for view functions
struct StakeInfoView {
  address owner;
  uint32 startEpoch;
  uint32 endEpoch;
  uint256[] tokenIds;
}

struct NFTStakingManagerSettings {
  address validatorManager;
  address license;
  uint32 initialEpochTimestamp;
  uint32 epochDuration;
  uint64 licenseWeight;
  uint256 epochRewards;
  uint16 maxLicensesPerValidator;
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

  struct NFTStakingManagerStorage {
    ValidatorManager manager;
    IERC721 licenseContract;
    uint16 maxLicensesPerValidator; // 100
    uint32 currentTotalStakedLicenses;
    uint32 initialEpochTimestamp; // 1716864000 2024-05-27 00:00:00 UTC
    uint32 epochDuration; // 1 days
    uint64 licenseWeight; // 1000
    uint256 epochRewards; // 1_369_863 (2_500_000_000 / (365 * 5)) * 1 ether
    // stakeId = validationId but in future could also be delegationId if we support that
    EnumerableSet.Bytes32Set stakeIds;
    mapping(bytes32 stakeId => StakeInfo) stakeInfo;
    mapping(uint32 epochNumber => EpochInfo) epochInfo;
    // We dont xfer nft to this contract, we just mark it as locked
    mapping(uint256 tokenId => bytes32 stakeID) tokenLockedBy;
    // Ensure that we only ever mint rewards once for a given epochNumber/tokenId combo
    mapping(uint32 epochNumber => mapping(uint256 tokenId => bool isRewardsMinted)) isRewardsMinted;
  }

  NFTStakingManagerStorage private _storage;

  constructor() {
    _disableInitializers();
  }

  function initialize(NFTStakingManagerSettings memory settings) public initializer {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();

    $.manager = ValidatorManager(settings.validatorManager);
    $.licenseContract = IERC721(settings.license);
    $.initialEpochTimestamp = settings.initialEpochTimestamp;
    $.epochDuration = settings.epochDuration;
    $.licenseWeight = settings.licenseWeight;
    $.epochRewards = settings.epochRewards;
    $.maxLicensesPerValidator = settings.maxLicensesPerValidator;
  }

  function initiateValidatorRegistration(
    bytes memory nodeID,
    bytes memory blsPublicKey,
    PChainOwner memory remainingBalanceOwner,
    PChainOwner memory disableOwner,
    uint256[] calldata tokenIds
  ) public returns (bytes32) {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    if (tokenIds.length == 0 || tokenIds.length > $.maxLicensesPerValidator) {
      revert("Invalid license count");
    }
    uint64 weight = uint64(tokenIds.length * $.licenseWeight);
    bytes32 stakeId = $.manager.initiateValidatorRegistration(
      nodeID,
      blsPublicKey,
      uint64(block.timestamp + 1 days),
      remainingBalanceOwner,
      disableOwner,
      weight
    );
    _lockTokens(stakeId, tokenIds);
    StakeInfo storage newStake = $.stakeInfo[stakeId];
    newStake.owner = msg.sender;
    newStake.tokenIds = tokenIds;

    // should we do something with stakeIds here

    return stakeId;
  }

  function completeValidatorRegistration(uint32 messageIndex) external returns (bytes32) {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    bytes32 stakeId = $.manager.completeValidatorRegistration(messageIndex);
    StakeInfo storage stake = $.stakeInfo[stakeId];
    $.currentTotalStakedLicenses += uint32(stake.tokenIds.length);
    stake.startEpoch = getCurrentEpoch();
    return stakeId;
  }

  function initiateValidatorRemoval(bytes32 stakeId) external {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    StakeInfo storage stake = $.stakeInfo[stakeId];
    if (stake.owner != msg.sender) revert UnauthorizedOwner(msg.sender);
    stake.endEpoch = getCurrentEpoch();
    $.currentTotalStakedLicenses -= uint32(stake.tokenIds.length);
    $.manager.initiateValidatorRemoval(stakeId);
  }

  function completeValidatorRemoval(uint32 messageIndex) external returns (bytes32) {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    bytes32 stakeId = $.manager.completeValidatorRemoval(messageIndex);
    StakeInfo storage stake = $.stakeInfo[stakeId];
    _unlockTokens(stakeId, stake.tokenIds);
    return stakeId;
  }

  // Anyone can call. Must be called right **after** a new epoch has started, and we will
  // snapshot the total staked licenses for the prev epoch
  // TODO what happens if we miss an epoch? Maybe admin fn to hardcode a snapshot?
  function rewardsSnapshot() external {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    // what to do if this is the first epoch? then I guess it can't be called
    if (getCurrentEpoch() == 0) revert("second epoch has not started yet");
    uint32 lastEpoch = getCurrentEpoch() - 1;
    if ($.epochInfo[lastEpoch].totalStakedLicenses != 0) {
      revert("Rewards already snapped for this epoch");
    }
    $.epochInfo[lastEpoch].totalStakedLicenses = $.currentTotalStakedLicenses;
  }

  // Anyone can call mintRewards functions to mint rewards (prob backend cron process)
  // No special permissions necessary. In future this could accept uptime proof as well.

  function mintRewards(uint32 epochNumber, bytes32[] calldata stakeIds) external {
    for (uint256 i = 0; i < stakeIds.length; i++) {
      _mintRewards(epochNumber, stakeIds[i]);
    }
  }

  function _mintRewards(uint32 epochNumber, bytes32 stakeId) internal {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    StakeInfo storage stake = $.stakeInfo[stakeId];

    if (stake.owner == address(0)) {
      revert("Stake does not exist");
    }

    // TODO: Handle the case where there are no licenses staked
    if ($.epochInfo[epochNumber].totalStakedLicenses == 0) {
      revert("Rewards not snapped for this epoch");
    }

    if (epochNumber < stake.startEpoch || (epochNumber > stake.endEpoch && stake.endEpoch != 0)) {
      revert EpochOutOfRange(epochNumber, stake.startEpoch, stake.endEpoch);
    }
    for (uint256 i = 0; i < stake.tokenIds.length; i++) {
      // TODO if either of these happen it seems unrecoverable? How would we fix?
      // admin fn to manually add data to rewards and locked mappings?
      if ($.tokenLockedBy[stake.tokenIds[i]] != stakeId) {
        revert("Token not locked by this stakeId");
      }
      if ($.isRewardsMinted[epochNumber][stake.tokenIds[i]]) {
        revert("Rewards already minted for this tokenId");
      }
      $.isRewardsMinted[epochNumber][stake.tokenIds[i]] = true;
    }
    uint256 rewards = calculateRewardsPerLicense(epochNumber) * stake.tokenIds.length;
    stake.claimableRewardsPerEpoch[epochNumber] = rewards;
    stake.claimableEpochNumbers.add(uint256(epochNumber));
    INativeMinter(0x0200000000000000000000000000000000000001).mintNativeCoin(address(this), rewards);
    emit RewardsMinted(epochNumber, stakeId, rewards);
  }

  function claimRewards(bytes32 stakeId, uint32 maxEpochs)
    external
    returns (uint256, uint32[] memory)
  {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    StakeInfo storage stake = $.stakeInfo[stakeId];

    if (stake.owner != msg.sender) revert UnauthorizedOwner(msg.sender);
    if (maxEpochs > stake.claimableEpochNumbers.length()) {
      maxEpochs = uint32(stake.claimableEpochNumbers.length());
    }

    uint256 totalRewards = 0;
    uint32[] memory claimedEpochNumbers = new uint32[](maxEpochs);

    for (uint32 i = 0; i < maxEpochs; i++) {
      uint32 epochNumber = uint32(stake.claimableEpochNumbers.at(i));
      uint256 rewards = stake.claimableRewardsPerEpoch[epochNumber];

      // State changes
      claimedEpochNumbers[i] = epochNumber;
      totalRewards += rewards;
      stake.claimableEpochNumbers.remove(uint256(epochNumber));
      stake.claimableRewardsPerEpoch[epochNumber] = 0;
    }

    // Events (after all state changes)
    for (uint32 i = 0; i < maxEpochs; i++) {
      emit RewardsClaimed(
        claimedEpochNumbers[i], stakeId, stake.claimableRewardsPerEpoch[claimedEpochNumbers[i]]
      );
    }

    payable(stake.owner).sendValue(totalRewards);
    return (totalRewards, claimedEpochNumbers);
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

  function _unlockTokens(bytes32 stakeId, uint256[] memory tokenIds) internal {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    StakeInfo storage stake = $.stakeInfo[stakeId];
    address owner = stake.owner;
    for (uint256 i = 0; i < tokenIds.length; i++) {
      $.tokenLockedBy[tokenIds[i]] = bytes32(0);
    }
    emit TokensUnlocked(owner, stakeId, tokenIds);
  }

  // these helpers should be public? for easy calling from front end etc?

  function calculateRewardsPerLicense(uint32 epochNumber) public view returns (uint256) {
    // maybe only allow checking for currentEpoch-1 or earlier?
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    return $.epochRewards / $.epochInfo[epochNumber].totalStakedLicenses;
  }

  function getEpochByTimestamp(uint32 timestamp) public view returns (uint32) {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    return (timestamp - $.initialEpochTimestamp) / $.epochDuration;
  }

  function getCurrentEpoch() public view returns (uint32) {
    return getEpochByTimestamp(uint32(block.timestamp));
  }

  function getCurrentTotalStakedLicenses() external view returns (uint32) {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    return $.currentTotalStakedLicenses;
  }

  function getTokenLockedBy(uint256 tokenId) external view returns (bytes32) {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    return $.tokenLockedBy[tokenId];
  }

  function getStakeIds() external view returns (bytes32[] memory) {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    return $.stakeIds.values();
  }

  function getStakeInfoView(bytes32 stakeId) external view returns (StakeInfoView memory) {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    StakeInfo storage stake = $.stakeInfo[stakeId];
    return StakeInfoView({
      owner: stake.owner,
      tokenIds: stake.tokenIds,
      startEpoch: stake.startEpoch,
      endEpoch: stake.endEpoch
    });
  }

  function getStakeRewardsForEpoch(bytes32 stakeId, uint32 epoch) external view returns (uint256) {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    return $.stakeInfo[stakeId].claimableRewardsPerEpoch[epoch];
  }

  function _authorizeUpgrade(address newImplementation)
    internal
    override
    onlyRole(DEFAULT_ADMIN_ROLE)
  { }
}
