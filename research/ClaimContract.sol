// SPDX-License-Identifier: MIT

pragma solidity ^0.8.25;

import { Address } from "@openzeppelin-contracts-5.3.0/utils/Address.sol";
import { AccessControlUpgradeable } from
  "@openzeppelin-contracts-upgradeable-5.3.0/access/AccessControlUpgradeable.sol";
import { Initializable } from
  "@openzeppelin-contracts-upgradeable-5.3.0/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from
  "@openzeppelin-contracts-upgradeable-5.3.0/proxy/utils/UUPSUpgradeable.sol";

// ClaimRewards is a contract that allows users to claim rewards from a vault.

// TODO figure out best most flexible way to structure roles and perms

contract ClaimRewards is Initializable, AccessControlUpgradeable, UUPSUpgradeable {
  using Address for address payable;

  bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

  mapping(address => uint256) public userBalances;
  // Each uint256 can store 256 epochs worth of reward status
  mapping(address => mapping(uint256 => uint256)) public userEpochRewardsDepositedBitmap;

  event RewardsDeposited(uint32 indexed epoch, address indexed user, uint256 amount);
  event RewardsClaimed(address indexed user, uint256 amount);
  event RewardsAdjusted(address indexed user, uint256 oldAmount, uint256 newAmount);

  error ArrayLengthMismatch();
  error UserAlreadyRewarded();
  error ZeroAddress();
  error InvalidAmount();
  error InsufficientRewardsError(uint256 requested, uint256 available);

  constructor() {
    _disableInitializers();
  }

  function initialize(address defaultAdmin, address upgrader) public initializer {
    __AccessControl_init();
    __UUPSUpgradeable_init();

    _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
    _grantRole(UPGRADER_ROLE, upgrader);
  }

  // So the flow would be the off-chain program does:
  // Query StakingContract to get map of userAddr => licenseCount
  // Sweep any gas fees from GasContract
  // Calculate rewardPerLicense
  // Calculate rewardPerUser
  // call depositRewards(epoch, userAddr[], amt[]) as many times as necessary
  function depositRewards(uint32 epoch, address[] calldata users, uint256[] calldata amounts)
    public
    payable
    onlyRole(DEFAULT_ADMIN_ROLE)
  {
    // Check arrays have same length
    if (users.length != amounts.length) {
      revert ArrayLengthMismatch();
    }

    uint256 total;
    for (uint256 i = 0; i < users.length; i++) {
      // Accumulate total while processing each entry
      total += amounts[i];
      if (users[i] == address(0)) revert ZeroAddress();
      if (isUserRewarded(users[i], epoch)) revert UserAlreadyRewarded();
      _setUserRewarded(users[i], epoch);
      userBalances[users[i]] += amounts[i];
      emit RewardsDeposited(epoch, users[i], amounts[i]);
    }

    // Check total after loop
    if (total != msg.value) revert InvalidAmount();
  }

  function claimRewards(uint256 amount) public {
    if (userBalances[msg.sender] < amount) {
      revert InsufficientRewardsError(amount, userBalances[msg.sender]);
    }
    userBalances[msg.sender] -= amount;
    payable(msg.sender).sendValue(amount);
    emit RewardsClaimed(msg.sender, amount);
  }

  /// @dev Allows for fixing any mistakes in the off-chain rewards calculations.
  function setRewards(address user, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
    if (user == address(0)) revert ZeroAddress();
    uint256 oldAmount = userBalances[user];
    userBalances[user] = amount;
    emit RewardsAdjusted(user, oldAmount, amount);
  }

  // Helper functions to manage the bitmap
  function isUserRewarded(address user, uint32 epoch) public view returns (bool) {
    uint256 wordIndex = epoch / 256;
    uint256 bitIndex = epoch % 256;
    uint256 word = userEpochRewardsDepositedBitmap[user][wordIndex];
    return (word & (1 << bitIndex)) != 0;
  }

  function _setUserRewarded(address user, uint32 epoch) internal {
    uint256 wordIndex = epoch / 256;
    uint256 bitIndex = epoch % 256;
    userEpochRewardsDepositedBitmap[user][wordIndex] |= (1 << bitIndex);
  }

  function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) { }
}
