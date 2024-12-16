// SPDX-License-Identifier: Ecosystem

pragma solidity 0.8.25;

import "@openzeppelin/contracts-upgradeable/metatx/ERC2771ContextUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IValidatorManager, ValidatorRegistrationInput, ConversionData, PChainOwner, ValidatorStatus} from "../interfaces/IValidatorManager.sol";
import {IRewardCalculator} from "../interfaces/IRewardCalculator.sol";
import {IStakingManager, StakingInput} from "../interfaces/IStakingManager.sol";


contract StakingManager is IStakingManager, UUPSUpgradeable, OwnableUpgradeable {

  struct ValidatorInfo {
    address owner;
    address tokenAddress; // address(0) for native
    uint256 amount;
    uint64 weight;
    // uint16 delegationFeeBips;
    uint64 minimumStakeDuration;
  }

  error InvalidValidationID(bytes32 validationID);
  error InvalidValidatorStatus(ValidatorStatus status);
  error InvalidStakeAmount(uint256 stakeAmount);
  error InvalidMinStakeDuration(uint64 minStakeDuration);

  /// @custom:storage-location erc7201:gogopool.storage.StakingManagerStorage
  struct StakingManagerStorage {
    /// @notice The minimum amount of stake required to be a validator.
    uint256 minimumStakeAmount;
    /// @notice The maximum amount of stake allowed to be a validator.
    uint256 maximumStakeAmount;
    /// @notice The minimum amount of time in seconds a validator must be staked for. Must be at least {churnPeriodSeconds}.
    uint64 minimumStakeDuration;

    /// @notice The reward calculator for this validator manager.
    IRewardCalculator rewardCalculator;

    /// @notice Address of the ValidatorManager contract.
    IValidatorManager validatorManager;

    /// @notice Maps the validation ID to its requirements.
    mapping(bytes32 validationID => ValidatorInfo) validatorInfo;
  }

  error InvalidValidator(address validator);

  // keccak256(abi.encode(uint256(keccak256("gogopool.storage.StakingManagerStorage")) - 1)) & ~bytes32(uint256(0xff));
  bytes32 public constant STORAGE_LOCATION = 0x81773fca73a14ca21edf1cadc6ec0b26d6a44966f6e97607e90422658d423500;

  function _getStorage() private pure returns (StakingManagerStorage storage $) {
    // solhint-disable-next-line no-inline-assembly
    assembly {
      $.slot := STORAGE_LOCATION
    }
  }

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize(IValidatorManager validatorManager) public initializer {
    StakingManagerStorage storage $ = _getStorage();
    $.validatorManager = validatorManager;
    // TODO settings
    $.minimumStakeAmount = 100;
    $.maximumStakeAmount = 1000000;
    $.minimumStakeDuration = 1000;
    __Ownable_init(msg.sender);
    __UUPSUpgradeable_init();
  }

  function initializeStake(StakingInput calldata input) payable external returns (bytes32) {
    StakingManagerStorage storage $ = _getStorage();
    if (input.tokenAddress == address(0)) { // Native token
      require(msg.value == input.amount, "Incorrect amount sent");
    } else {
      // TODO figure out how to get it all to work with erc20s as well (with minting rewards both ways etc)
      //IERC20(input.tokenAddress).transferFrom(input.staker, address(this), input.amount);
    }
    if (input.minimumStakeDuration < $.minimumStakeDuration) {
      revert InvalidMinStakeDuration(input.minimumStakeDuration);
    }
    if (input.amount < $.minimumStakeAmount || input.amount > $.maximumStakeAmount) {
      revert InvalidStakeAmount(input.amount);
    }

    uint256 lockedValue = _lock(input.amount);
    uint64 weight = valueToWeight(lockedValue);
    bytes32 validationID = $.validatorManager.initializeValidatorRegistration(input.input, weight);

    address owner = _msgSender();
    $.validatorInfo[validationID].owner = owner;
    $.validatorInfo[validationID].tokenAddress = input.tokenAddress;
    $.validatorInfo[validationID].amount = input.amount;
    $.validatorInfo[validationID].weight = weight;
    $.validatorInfo[validationID].minimumStakeDuration = input.minimumStakeDuration;

    return validationID;
  }

  function completeStake(uint32 messageIndex) external returns (bytes32) {
    StakingManagerStorage storage $ = _getStorage();
    $.validatorManager.completeValidatorRegistration(messageIndex);
  }
  
  function valueToWeight(uint256 value) public view returns (uint64) {
    // TODO maybe move this out to a rewardsCalc-like contract?
    uint256 weight = value / 1;
    if (weight == 0 || weight > type(uint64).max) {
        revert InvalidStakeAmount(value);
    }
    return uint64(weight);
  }

  function _lock(uint256 amount) internal returns (uint256) {
    // TODO maybe use inheritance? 
    return amount;
  }

  // Add authorization for upgrades
  function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}