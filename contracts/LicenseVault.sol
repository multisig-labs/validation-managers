// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC721Receiver} from "@openzeppelin-contracts-5.2.0/token/ERC721/IERC721Receiver.sol";

import {Address} from "@openzeppelin-contracts-5.2.0/utils/Address.sol";
import {AccessControlDefaultAdminRulesUpgradeable} from
  "@openzeppelin-contracts-upgradeable-5.2.0/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin-contracts-upgradeable-5.2.0/proxy/utils/UUPSUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin-contracts-upgradeable-5.2.0/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin-contracts-upgradeable-5.2.0/utils/ReentrancyGuardUpgradeable.sol";
import {PChainOwner} from "icm-contracts-8817f47/contracts/validator-manager/ACP99Manager.sol";

import {EnumerableSet} from "@openzeppelin-contracts-5.2.0/utils/structs/EnumerableSet.sol";

import {NFTStakingManager} from "./NFTStakingManager.sol";
import {NodeLicense} from "./tokens/NodeLicense.sol";
import {ReceiptToken} from "./tokens/ReceiptToken.sol";

// TODO also store $._pendingRegisterValidationMessages[validationID] = registerL1ValidatorMessage; from the validator manager
struct StakeInfo {
  bytes nodeID;
  bytes blsPublicKey;
  bytes blsPop;
  uint256[] tokenIds;
  bytes registerL1ValidatorMessage;
}

struct DepositorInfo {
  uint32 licenseCount;
  uint32 withdrawalRequest;
  uint32 withdrawalRequestTimestamp;
  uint256 claimableRewards;
  uint256 receiptId;
}

/// @dev This vault only works if the NFTs are all fungible.
contract LicenseVault is
  ReentrancyGuardUpgradeable,
  AccessControlDefaultAdminRulesUpgradeable,
  PausableUpgradeable,
  UUPSUpgradeable,
  IERC721Receiver
{
  using Address for address payable;
  using EnumerableSet for EnumerableSet.UintSet;
  using EnumerableSet for EnumerableSet.Bytes32Set;
  using EnumerableSet for EnumerableSet.AddressSet;

  bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
  uint32 public constant WITHDRAWAL_DELAY = 14 days;

  NodeLicense public nodeLicense;
  ReceiptToken public receiptToken;
  NFTStakingManager public nftStakingManager;
  // These will be used for each new hardware node created
  PChainOwner public remainingBalanceOwner;
  PChainOwner public disableOwner;

  uint256 public totalDepositedLicenses;
  // As NFTs are added, we lump them all together and do not track which user had which id
  // This is the set that are in this contract and not staking
  EnumerableSet.UintSet unstakedTokenIds;
  // These are the ones that have been deposited to the staking contract
  EnumerableSet.UintSet stakedTokenIds;
  EnumerableSet.AddressSet depositors;
  EnumerableSet.Bytes32Set stakeIds;
  mapping(address depositor => DepositorInfo depositorInfo) depositorInfo;
  mapping(bytes32 stakeId => StakeInfo stakeInfo) stakeInfo;

  event LicensesDeposited(address depositor, uint32 count);
  event LicensesWithdrawn(address withdrawer, uint32 count);
  event WithdrawalRequested(address withdrawer, uint32 count);
  event ValidatorStaked(bytes32 indexed stakeId, uint256[] tokenIds);
  event ValidatorUnstakingInitiated(bytes32 indexed stakeId);

  error LicensesNotAvailableForWithdrawal();
  error NotEnoughLicenses();
  error NoLicensesDeposited();
  error NoWithdrawalRequest();
  error NoRewardsToClaim();
  error WithdrawalAlreadyRequested();
  error WithdrawalDelayNotMet();

  // Initializer instead of constructor
  function initialize(
    address nodeLicense_,
    address receiptToken_,
    address nftStakingManager_,
    address initialAdmin,
    PChainOwner calldata remainingBalanceOwner_,
    PChainOwner calldata disableOwner_
  ) external initializer {
    __ReentrancyGuard_init();
    __AccessControl_init();
    __Pausable_init();
    __UUPSUpgradeable_init();

    nodeLicense = NodeLicense(nodeLicense_);
    receiptToken = ReceiptToken(receiptToken_);
    nftStakingManager = NFTStakingManager(nftStakingManager_);
    remainingBalanceOwner = remainingBalanceOwner_;
    disableOwner = disableOwner_;
    _grantRole(DEFAULT_ADMIN_ROLE, initialAdmin);
    _grantRole(MANAGER_ROLE, initialAdmin);

    _pause();
  }

  function deposit(uint256[] calldata tokenIds) external nonReentrant {
    depositors.add(msg.sender);
    depositorInfo[msg.sender].licenseCount += uint32(tokenIds.length);
    totalDepositedLicenses += tokenIds.length;
    for (uint256 i = 0; i < tokenIds.length; i++) {
      unstakedTokenIds.add(tokenIds[i]);
      nodeLicense.transferFrom(msg.sender, address(this), tokenIds[i]);
    }
    // If depositor does not yet have a receipt, mint them one
    if (depositorInfo[msg.sender].receiptId == 0) {
      uint256 receiptId = receiptToken.mint(msg.sender);
      depositorInfo[msg.sender].receiptId = receiptId;
    }
    emit LicensesDeposited(msg.sender, uint32(tokenIds.length));
  }

  function requestWithdrawal(uint32 count) external nonReentrant {
    if (depositorInfo[msg.sender].withdrawalRequest != 0) {
      revert WithdrawalAlreadyRequested();
    }
    if (count > depositorInfo[msg.sender].licenseCount) {
      revert NotEnoughLicenses();
    }

    depositorInfo[msg.sender].withdrawalRequest = count;
    depositorInfo[msg.sender].withdrawalRequestTimestamp = uint32(block.timestamp);
    emit WithdrawalRequested(msg.sender, count);
  }

  // Assumes we actually have enough NFTs back from the staking contract
  // TODO enforce a time delay
  function completeWithdrawal() external nonReentrant {
    DepositorInfo memory info = depositorInfo[msg.sender];

    if (info.withdrawalRequest == 0) {
      revert NoWithdrawalRequest();
    }
    if (info.withdrawalRequest > unstakedTokenIds.length()) {
      revert LicensesNotAvailableForWithdrawal();
    }
    if (block.timestamp < info.withdrawalRequestTimestamp + WITHDRAWAL_DELAY) {
      revert WithdrawalDelayNotMet();
    }

    totalDepositedLicenses -= info.withdrawalRequest;

    // Collect all NFTs to transfer
    uint256[] memory tokenIdsToTransfer = new uint256[](info.withdrawalRequest);
    for (uint256 i = 0; i < info.withdrawalRequest; i++) {
      uint256 lastIndex = unstakedTokenIds.length() - 1;
      uint256 lastTokenId = unstakedTokenIds.at(lastIndex);
      unstakedTokenIds.remove(lastTokenId);
      info.licenseCount--;
      tokenIdsToTransfer[i] = lastTokenId;
      nodeLicense.transferFrom(address(this), msg.sender, lastTokenId);
    }

    info.withdrawalRequest = 0;

    if (info.licenseCount == 0) {
      depositors.remove(msg.sender);
      receiptToken.burn(info.receiptId);
      info.receiptId = 0;
    }

    // Write back to storage
    depositorInfo[msg.sender] = info;

    emit LicensesWithdrawn(msg.sender, uint32(tokenIdsToTransfer.length));
  }

  function balanceOf(address account) external view returns (uint256) {
    return depositorInfo[account].licenseCount;
  }

  // Off-Chain fns

  function stakeValidator(bytes memory nodeID, bytes memory blsPublicKey, bytes memory blsPop, uint256 numTokens)
    external
    onlyRole(MANAGER_ROLE)
    returns (bytes32)
  {
    if (numTokens > unstakedTokenIds.length()) revert NotEnoughLicenses();
    uint256[] memory tokenIds = new uint256[](numTokens);
    for (uint256 i = 0; i < numTokens; i++) {
      uint256 lastIndex = unstakedTokenIds.length() - 1;
      uint256 lastTokenId = unstakedTokenIds.at(lastIndex);
      unstakedTokenIds.remove(lastTokenId);
      stakedTokenIds.add(lastTokenId);
      tokenIds[i] = lastTokenId;
    }
    bytes32 stakeId = nftStakingManager.initiateValidatorRegistration(nodeID, blsPublicKey, remainingBalanceOwner, disableOwner, tokenIds);
    stakeInfo[stakeId] = StakeInfo({
      nodeID: nodeID,
      blsPublicKey: blsPublicKey,
      blsPop: blsPop,
      tokenIds: tokenIds,
      registerL1ValidatorMessage: bytes("") // TODO
    });
    stakeIds.add(stakeId);
    emit ValidatorStaked(stakeId, tokenIds);
    return stakeId;
  }

  /// @dev The tokenIds will not be unlocked until NFTStakingManager.completeValidatorRemoval is called
  function unstakeValidator(bytes32 stakeId) external onlyRole(MANAGER_ROLE) {
    stakeIds.remove(stakeId);
    nftStakingManager.initiateValidatorRemoval(stakeId);
    emit ValidatorUnstakingInitiated(stakeId);
  }

  // Calls into NFTStakingManager to claim rewards and distribute evenly to all depositors
  // TODO check gas limits, expect MAX of 10,000 depositors
  // TODO check precision loss
  /// @dev maxEpochs is the number of unclaimed epochs to claim rewards for, allowing for claiming
  ///      a subset of epochs if gas costs are too high
  function claimValidatorRewards(bytes32 stakeId, uint32 maxEpochs) external onlyRole(MANAGER_ROLE) {
    (uint256 rewards,) = nftStakingManager.claimRewards(stakeId, maxEpochs);

    uint256 totalLicenses = totalDepositedLicenses;
    if (totalLicenses == 0) revert NoLicensesDeposited();

    for (uint256 i = 0; i < depositors.length(); i++) {
      address currentDepositor = depositors.at(i);
      uint256 depositorLicenses = depositorInfo[currentDepositor].licenseCount;

      // Calculate: (rewards * depositorLicenses) / totalLicenses
      // Multiply first to maintain precision
      uint256 rewardForDepositor = (rewards * depositorLicenses) / totalLicenses;

      depositorInfo[currentDepositor].claimableRewards += rewardForDepositor;
    }
  }

  function claimDepositorRewards() external nonReentrant {
    uint256 amount = depositorInfo[msg.sender].claimableRewards;
    if (amount == 0) revert NoRewardsToClaim();
    depositorInfo[msg.sender].claimableRewards = 0;
    payable(msg.sender).sendValue(amount);
  }

  function getClaimableRewards(address depositor) external view returns (uint256) {
    return depositorInfo[depositor].claimableRewards;
  }

  function getStakeInfo(bytes32 stakeId) external view returns (StakeInfo memory) {
    return stakeInfo[stakeId];
  }

  function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
    return this.onERC721Received.selector;
  }

  function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}
