// SPDX-License-Identifier: MIT

pragma solidity ^0.8.25;

import {Address} from "@openzeppelin-contracts-5.2.0/utils/Address.sol";
import {AccessControlUpgradeable} from "@openzeppelin-contracts-upgradeable-5.2.0/access/AccessControlUpgradeable.sol";
import {Initializable} from "@openzeppelin-contracts-upgradeable-5.2.0/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin-contracts-upgradeable-5.2.0/proxy/utils/UUPSUpgradeable.sol";

// ClaimRewards is a contract that allows users to claim rewards from a vault.

// TODO figure out best most flexible way to structure roles and perms

contract ClaimRewards is Initializable, AccessControlUpgradeable, UUPSUpgradeable {
  using Address for address payable;

  bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

  mapping(address => uint256) public rewards;

  event RewardsAdded(address indexed user, uint256 amount);
  event RewardsClaimed(address indexed user, uint256 amount);
  event RewardsAdjusted(address indexed user, uint256 oldAmount, uint256 newAmount);

  error ArrayLengthMismatch();
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

  function claimRewards(uint256 amount) public {
    if (rewards[msg.sender] < amount) {
      revert InsufficientRewardsError(amount, rewards[msg.sender]);
    }
    rewards[msg.sender] -= amount;
    payable(msg.sender).sendValue(amount);
    emit RewardsClaimed(msg.sender, amount);
  }

  // TODO does this even need a role? Anyone can add rewards right? free money!
  // In this scenario, some off-chain actor needs to use nativeMinter precompile to mint the rewards,
  // then call this function to distribute them.
  function addRewards(address[] calldata users, uint256[] calldata amounts) public payable onlyRole(DEFAULT_ADMIN_ROLE) {
    // Check arrays have same length
    if (users.length != amounts.length) {
      revert ArrayLengthMismatch();
    }

    // Check total matches msg.value
    uint256 total;
    for (uint256 i = 0; i < users.length; i++) {
      // Accumulate total while processing each entry
      total += amounts[i];
      if (users[i] == address(0)) revert ZeroAddress();
      rewards[users[i]] += amounts[i];
      emit RewardsAdded(users[i], amounts[i]);
    }

    // Check total after loop
    if (total != msg.value) revert InvalidAmount();
  }

  // TODO Another idea is to have this contract be allowed to use NativeMinter precompile.
  // So the flow would be the off-chain program does:
  // Query StakingContract to get map of userAddr => licenseCount
  // Calculate rewardPerLicense
  // Calculate rewardPerUser
  // call mintRewards()
  // call addRewards(userAddr[], amt[])
  // In this case addRewards is not payable, as mintRewards put the funds directly into this contract
  // Advantage is this would be the only contract that can mint, and only to itself. Better security.
  // How to handle if we missed a day due to downtime or something? Just do 2 epochs in a row?
  function mintRewards(uint16 epoch) external onlyRole(DEFAULT_ADMIN_ROLE) {
    // init with a constant rewardPerEpoch = 123 ether
    // epoch is the count of days. each day is a set, static reward amt.
    // would need mapping to track if an epoch was minted or not
    // mapping(uint16 => bool) public epochMinted;
    // maybe track lastEpoch and only allow minting if lastEpoch + 1 == epoch
    if (epochMinted[epoch]) revert EpochAlreadyMinted();
    NativeMinter.mint(address(this), rewardPerEpoch);
    epochMinted[epoch] = true;
  }

  function setRewards(address user, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
    if (user == address(0)) revert ZeroAddress();
    uint256 oldAmount = rewards[user];
    rewards[user] = amount;
    emit RewardsAdjusted(user, oldAmount, amount);
  }

  function rescueERC20(address token) external onlyRole(DEFAULT_ADMIN_ROLE) {
    IERC20(token).transferFrom(address(this), msg.sender, IERC20(token).balanceOf(address(this)));
  }

  function rescueETH(uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
    payable(msg.sender).sendValue(amount);
  }

  function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}
}
