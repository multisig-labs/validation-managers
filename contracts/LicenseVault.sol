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

contract LicenseVault is
  ReentrancyGuardUpgradeable,
  AccessControlDefaultAdminRulesUpgradeable,
  PausableUpgradeable,
  UUPSUpgradeable,
  IERC721Receiver
{
  using Address for address payable;
  using EnumerableSet for EnumerableSet.UintSet;

  // Define roles
  bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

  // keccak256(abi.encode(uint256(keccak256("ggp.license-vault.storage")) - 1)) & ~bytes32(uint256(0xff));
  bytes32 private constant STORAGE_SLOT = 0x2f6a4ce7e0d803b1db7346f89a93540904d483a86cfc404f47564789646c7600;

  // Struct to hold all state variables
  struct Storage {
    IERC721 nftContract;
    // As NFTs are added, we lump them all together and do not track which user had which id
    // This is the set that are in this contract and not staking
    EnumerableSet.UintSet unstakedNftIds;
    // These are the ones that have been xfered out to the staking contract
    EnumerableSet.UintSet stakedNftIds;
    // Track how many licenses each user has deposited
    mapping(address => uint32) userLicenseCount;
    // Track how many licenses each user has requested to withdraw
    mapping(address => uint32) userWithdrawalRequests;
  }

  // Custom errors
  error LicenseNotAvailableForWithdrawal();
  error NotEnoughLicenses();
  error WithdrawalAlreadyRequested();
  error NoWithdrawalRequest();

  event LicensesDeposited(address depositor, uint32 count);
  event LicensesWithdrawn(address withdrawer, uint32 count);
  event WithdrawalRequested(address withdrawer, uint32 count);
  // Function to access the storage struct

  function _storage() private pure returns (Storage storage $) {
    bytes32 slot = STORAGE_SLOT;
    // solhint-disable-next-line no-inline-assembly
    assembly {
      $.slot := slot
    }
  }

  // Initializer instead of constructor
  function initialize(address _nftContract, address _initialAdmin) external initializer {
    __ReentrancyGuard_init();
    __AccessControl_init();
    __Pausable_init();
    __UUPSUpgradeable_init();

    Storage storage s = _storage();
    s.nftContract = IERC721(_nftContract);

    _grantRole(DEFAULT_ADMIN_ROLE, _initialAdmin);

    _pause();
  }

  function deposit(uint256[] calldata nftIds) external nonReentrant {
    Storage storage $ = _storage();

    for (uint256 i = 0; i < nftIds.length; i++) {
      $.nftContract.safeTransferFrom(msg.sender, address(this), nftIds[i]);
      $.unstakedNftIds.add(nftIds[i]);
      $.userLicenseCount[msg.sender]++;
    }
    emit LicensesDeposited(msg.sender, nftIds.length);
  }

  function requestWithdrawal(uint32 count) external nonReentrant {
    Storage storage $ = _storage();
    if ($.userWithdrawalRequests[msg.sender] != 0) {
      revert WithdrawalAlreadyRequested();
    }
    if (count > $.userLicenseCount[msg.sender]) {
      revert NotEnoughLicenses();
    }

    $.userWithdrawalRequests[msg.sender] = count;
    emit WithdrawalRequested(msg.sender, count);
  }

  // Assumes we actually have enough NFTs back from the staking contract
  function withdraw() external nonReentrant {
    Storage storage $ = _storage();
    if ($.userWithdrawalRequests[msg.sender] == 0) {
      revert NoWithdrawalRequest();
    }
    if ($.userWithdrawalRequests[msg.sender] > $.unstakedNftIds.length()) {
      revert LicenseNotAvailableForWithdrawal();
    }

    // First collect all NFTs to transfer
    uint256[] memory nftsToTransfer = new uint256[]($.userWithdrawalRequests[msg.sender]);
    for (uint256 i = 0; i < $.userWithdrawalRequests[msg.sender]; i++) {
      uint256 lastIndex = $.unstakedNftIds.length() - 1;
      uint256 lastNftId = $.unstakedNftIds.at(lastIndex);
      $.unstakedNftIds.remove(lastNftId);
      nftsToTransfer[i] = lastNftId;
    }
    // Then do a single batch transfer
    // TODO make sure ethix license contract supports batch transfers
    $.nftContract.safeBatchTransferFrom(address(this), msg.sender, nftsToTransfer);

    $.userWithdrawalRequests[msg.sender] = 0;
    emit LicensesWithdrawn(msg.sender, nftsToTransfer.length);
  }

  // Off-Chain fns

  function withdrawForStaking(uint256 limit) external onlyRole(MANAGER_ROLE) {
    Storage storage $ = _storage();
    if (limit > $.unstakedNftIds.length()) {
      limit = $.unstakedNftIds.length();
    }

    uint256[] memory nftsToTransfer = new uint256[](limit);

    for (uint256 i = 0; i < limit; i++) {
      uint256 nftId = $.unstakedNftIds.at(i);
      $.unstakedNftIds.remove(nftId);
      $.stakedNftIds.add(nftId);
      nftsToTransfer[i] = nftId;
    }
    $.nftContract.safeBatchTransferFrom(address(this), msg.sender, nftsToTransfer);
  }

  function depositFromStaking(uint256[] calldata nftIds) external onlyRole(MANAGER_ROLE) {
    Storage storage $ = _storage();
    for (uint256 i = 0; i < nftIds.length; i++) {
      $.stakedNftIds.remove(nftIds[i]);
      $.unstakedNftIds.add(nftIds[i]);
    }
    $.nftContract.safeBatchTransferFrom(msg.sender, address(this), nftIds);
  }

  function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
    return this.onERC721Received.selector;
  }
}
