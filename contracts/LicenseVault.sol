// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC721} from "@openzeppelin-contracts-5.2.0/token/ERC721/IERC721.sol";
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
import {IERC721Batchable} from "./tokens/IERC721Batchable.sol";

// TODO also get $._pendingRegisterValidationMessages[validationID] = registerL1ValidatorMessage; from the validator manager
struct StakeInfo {
  bytes32 stakeId;
  bytes nodeID;
  bytes blsPublicKey;
  bytes blsPop;
  uint256[] tokenIds;
  bytes registerL1ValidatorMessage;
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

  bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

  IERC721Batchable public licenseContract;
  NFTStakingManager public nftStakingManager;
  // These will be used for each new hardware node created
  PChainOwner public remainingBalanceOwner;
  PChainOwner public disableOwner;
  // As NFTs are added, we lump them all together and do not track which user had which id
  // This is the set that are in this contract and not staking
  EnumerableSet.UintSet unstakedTokenIds;
  // These are the ones that have been deposited to the staking contract
  EnumerableSet.UintSet stakedTokenIds;
  // Track how many licenses each user has deposited
  mapping(address depositor => uint32 count) licenseCount;
  // Track how many licenses each user has requested to withdraw
  mapping(address depositor => uint32 count) withdrawalRequest;
  // Track the stake info for each stakeId
  mapping(bytes32 stakeId => StakeInfo stakeInfo) stakeInfo;

  event LicensesDeposited(address depositor, uint32 count);
  event LicensesWithdrawn(address withdrawer, uint32 count);
  event WithdrawalRequested(address withdrawer, uint32 count);

  error LicensesNotAvailableForWithdrawal();
  error NotEnoughLicenses();
  error WithdrawalAlreadyRequested();
  error NoWithdrawalRequest();

  // Initializer instead of constructor
  function initialize(
    address licenseContract_,
    address nftStakingManager_,
    address initialAdmin,
    PChainOwner calldata remainingBalanceOwner_,
    PChainOwner calldata disableOwner_
  ) external initializer {
    __ReentrancyGuard_init();
    __AccessControl_init();
    __Pausable_init();
    __UUPSUpgradeable_init();

    licenseContract = IERC721Batchable(licenseContract_);
    nftStakingManager = NFTStakingManager(nftStakingManager_);
    remainingBalanceOwner = remainingBalanceOwner_;
    disableOwner = disableOwner_;
    _grantRole(DEFAULT_ADMIN_ROLE, initialAdmin);

    _pause();
  }

  function deposit(uint256[] calldata tokenIds) external nonReentrant {
    for (uint256 i = 0; i < tokenIds.length; i++) {
      unstakedTokenIds.add(tokenIds[i]);
      licenseCount[msg.sender]++;
    }
    licenseContract.safeBatchTransferFrom(msg.sender, address(this), tokenIds);
    // TODO mint soulbound receipt NFTs
    emit LicensesDeposited(msg.sender, uint32(tokenIds.length));
  }

  function requestWithdrawal(uint32 count) external nonReentrant {
    if (withdrawalRequest[msg.sender] != 0) {
      revert WithdrawalAlreadyRequested();
    }
    if (count > licenseCount[msg.sender]) {
      revert NotEnoughLicenses();
    }

    withdrawalRequest[msg.sender] = count;
    emit WithdrawalRequested(msg.sender, count);
  }

  // Assumes we actually have enough NFTs back from the staking contract
  function withdraw() external nonReentrant {
    if (withdrawalRequest[msg.sender] == 0) {
      revert NoWithdrawalRequest();
    }
    if (withdrawalRequest[msg.sender] > unstakedTokenIds.length()) {
      revert LicensesNotAvailableForWithdrawal();
    }

    // First collect all NFTs to transfer
    uint256[] memory tokenIdsToTransfer = new uint256[](withdrawalRequest[msg.sender]);
    for (uint256 i = 0; i < withdrawalRequest[msg.sender]; i++) {
      uint256 lastIndex = unstakedTokenIds.length() - 1;
      uint256 lastTokenId = unstakedTokenIds.at(lastIndex);
      unstakedTokenIds.remove(lastTokenId);
      tokenIdsToTransfer[i] = lastTokenId;
    }
    // Then do a single batch transfer
    // TODO make sure ethix license contract supports batch transfers
    licenseContract.safeBatchTransferFrom(address(this), msg.sender, tokenIdsToTransfer);
    // TODO burn the receipt NFTs
    withdrawalRequest[msg.sender] = 0;
    emit LicensesWithdrawn(msg.sender, uint32(tokenIdsToTransfer.length));
  }

  // Off-Chain fns

  function stakeValidator(bytes memory nodeID, bytes memory blsPublicKey, bytes memory blsPop, uint256 numTokens) external onlyRole(MANAGER_ROLE) {
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
      stakeId: stakeId,
      nodeID: nodeID,
      blsPublicKey: blsPublicKey,
      blsPop: blsPop,
      tokenIds: tokenIds,
      registerL1ValidatorMessage: bytes("") // TODO
    });
  }

  function unstakeValidator(bytes32 stakeId) external onlyRole(MANAGER_ROLE) {
    nftStakingManager.initiateValidatorRemoval(stakeId);
  }

  function getStakeInfo(bytes32 stakeId) external view returns (StakeInfo memory) {
    return stakeInfo[stakeId];
  }

  function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
    return this.onERC721Received.selector;
  }

  function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}
