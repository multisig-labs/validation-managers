// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Address} from "@openzeppelin-contracts-5.2.0/utils/Address.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {PChainOwner, Validator, ValidatorStatus} from "icm-contracts-8817f47/contracts/validator-manager/ACP99Manager.sol";
import {ValidatorManager} from "icm-contracts-8817f47/contracts/validator-manager/ValidatorManager.sol";
// import { IWarpMessenger } from "

contract NFTStakingManager {
  using Address for address payable;

  uint32 public constant INITIAL_EPOCH_TIMESTAMP = 1716864000; // 2024-05-27 00:00:00 UTC
  uint32 public constant EPOCH_DURATION = 1 days;
  uint64 public constant LICENSE_WEIGHT = 1000;
  uint256 public constant EPOCH_REWARDS = 1_369_863 ether; // (2_500_000_000 / (365 * 5)) * 1 ether;
  uint16 public constant MAX_LICENSES_PER_VALIDATOR = 100;

  error TokenAlreadyLocked(uint256 tokenId);
  error UnauthorizedOwner(address owner);
  error EpochOutOfRange(uint32 currentEpoch, uint32 startEpoch, uint32 endEpoch);

  event TokensLocked(address indexed owner, bytes32 indexed stakeId, uint256[] tokenIds);
  event TokensUnlocked(address indexed owner, bytes32 indexed stakeId, uint256[] tokenIds);
  event RewardsMinted(uint32 indexed epochNumber, bytes32 indexed stakeId, uint256 rewards);
  event RewardsClaimed(uint32 indexed epochNumber, bytes32 indexed stakeId, uint256 rewards);

  struct epochInfo {
    uint256 totalStakedLicenses;
  }

  struct StakeInfo {
    address owner;
    uint32 startEpoch;
    uint32 endEpoch;
    bytes32 validationId;
    uint256[] tokenIds;
    mapping(uint32 epochNumber => uint256 rewards) claimableRewardsPerEpoch; // will get set to zero when claimed
  }

  // keccak256(abi.encode(uint256(keccak256("gogopool.storage.NFTStakingManagerStorage")) - 1)) & ~bytes32(uint256(0xff));
  bytes32 public constant NFT_STAKING_MANAGER_STORAGE_LOCATION = 0xb2bea876b5813e5069ed55d22ad257d01245c883a221b987791b00df2f4dfa00;

  struct NFTStakingManagerStorage {
    ValidatorManager manager;
    IERC721 licenseContract;
    uint32 currentTotalStakedLicenses;
    mapping(uint32 epochNumber => epochInfo) epochInfo;
    // We dont xfer nft to this contract, we just mark it as locked
    mapping(uint256 tokenId => bytes32 stakeID) tokenLockedBy;
    // stakeId = validationId but in future could also be delegationId if we support that
    mapping(bytes32 stakeId => StakeInfo) stakeInfo;
    // Ensure that we only ever mint rewards once for a given epochNumber/tokenId combo
    // Gas is cheap so nested mapping is the clearest
    mapping(uint32 epochNumber => mapping(uint256 tokenId => bool isRewardsMinted)) isRewardsMinted;
  }

  NFTStakingManagerStorage private _storage;

  function initiateValidatorRegistration(
    bytes memory nodeID,
    bytes memory blsPublicKey,
    PChainOwner memory remainingBalanceOwner,
    PChainOwner memory disableOwner,
    uint256[] memory tokenIds
  ) public returns (bytes32) {
    if (tokenIds.length == 0 || tokenIds.length > MAX_LICENSES_PER_VALIDATOR) revert("Invalid license count");
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    uint64 weight = uint64(tokenIds.length * LICENSE_WEIGHT);
    bytes32 stakeId =
      $.manager.initiateValidatorRegistration(nodeID, blsPublicKey, uint64(block.timestamp + 1 days), remainingBalanceOwner, disableOwner, weight);
    // do not xfer, just mark tokens as locked by this stakeId
    // msg.sender must own all the tokens
    _lockTokens(stakeId, tokenIds);
    // create StakeInfo and add to mapping
    StakeInfo storage newStake = $.stakeInfo[stakeId];
    newStake.owner = msg.sender;
    newStake.tokenIds = tokenIds;
    newStake.validationId = stakeId;

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
  // snapshot the total staked licenses for the epoch
  // TODO what happens if we miss an epoch? Maybe admin fn to hardcode a snapshot?
  function rewardsSnapshot() external {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    uint32 lastEpoch = getCurrentEpoch() - 1;
    if ($.epochInfo[lastEpoch].totalStakedLicenses != 0) revert("Rewards already snapped for this epoch");
    $.epochInfo[lastEpoch].totalStakedLicenses = $.currentTotalStakedLicenses;
  }

  // Anyone can call this function to mint rewards (prob backend cron process)
  // In future this could accept uptime proof as well.
  function mintRewards(uint32 epochNumber, bytes32 stakeId) external {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    if ($.epochInfo[epochNumber].totalStakedLicenses == 0) revert("Rewards not snapped for this epoch");
    StakeInfo storage stake = $.stakeInfo[stakeId];
    uint32 currentEpoch = getCurrentEpoch();
    if (currentEpoch < stake.startEpoch || currentEpoch > stake.endEpoch) {
      revert EpochOutOfRange(currentEpoch, stake.startEpoch, stake.endEpoch);
    }
    for (uint256 i = 0; i < stake.tokenIds.length; i++) {
      // TODO if either of these happen it seems unrecoverable? How would we fix?
      // admin fn to manually add data to rewards and locked mappings?
      if ($.tokenLockedBy[stake.tokenIds[i]] != stakeId) revert("Token not locked by this stakeId");
      if ($.isRewardsMinted[epochNumber][stake.tokenIds[i]]) revert("Rewards already minted for this tokenId");
      $.isRewardsMinted[epochNumber][stake.tokenIds[i]] = true;
    }
    uint256 rewards = calculateRewardsPerLicense(epochNumber) * stake.tokenIds.length;
    stake.claimableRewardsPerEpoch[epochNumber] = rewards;
    // TODO mint rewards using nativeminter
    emit RewardsMinted(epochNumber, stakeId, rewards);
  }

  function claimRewards(bytes32 stakeId, uint32[] calldata epochNumbers) external {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    StakeInfo storage stake = $.stakeInfo[stakeId];
    if (stake.owner != msg.sender) revert UnauthorizedOwner(msg.sender);
    uint256 totalRewards = 0;
    for (uint32 i = 0; i < epochNumbers.length; i++) {
      uint256 rewards = stake.claimableRewardsPerEpoch[epochNumbers[i]];
      stake.claimableRewardsPerEpoch[epochNumbers[i]] = 0;
      emit RewardsClaimed(epochNumbers[i], stakeId, rewards);
      totalRewards += rewards;
    }
    payable(stake.owner).sendValue(totalRewards);
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
    return EPOCH_REWARDS / $.epochInfo[epochNumber].totalStakedLicenses;
  }

  function getEpochByTimestamp(uint32 timestamp) public pure returns (uint32) {
    return (timestamp - INITIAL_EPOCH_TIMESTAMP) / EPOCH_DURATION;
  }

  function getCurrentEpoch() public view returns (uint32) {
    return getEpochByTimestamp(uint32(block.timestamp));
  }
}
