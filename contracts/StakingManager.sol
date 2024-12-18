// SPDX-License-Identifier: Ecosystem

pragma solidity 0.8.25;

import "@openzeppelin/contracts-upgradeable/metatx/ERC2771ContextUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {IWarpMessenger, WarpMessage} from "@avalabs/subnet-evm-contracts@1.2.0/contracts/interfaces/IWarpMessenger.sol";
import {ValidatorMessages} from "./ValidatorMessages.sol";

import {ValidatorRegistrationInput, ConversionData, PChainOwner, ValidatorStatus, Validator} from "./interfaces/IValidatorManager.sol";
import {IERC20Mintable} from "./interfaces/IERC20Mintable.sol";
import {IPoAValidatorManager} from "./interfaces/IPoAValidatorManager.sol";
import {IRewardCalculator} from "./interfaces/IRewardCalculator.sol";
import {IStakingManager, StakingInput} from "./interfaces/IStakingManager.sol";

contract StakingManager is IStakingManager, UUPSUpgradeable, OwnableUpgradeable {
  IWarpMessenger public constant WARP_MESSENGER = IWarpMessenger(0x0200000000000000000000000000000000000005);

  struct ValidatorInfo {
    address owner;
    address tokenAddress; // address(0) for native
    uint256 amount;
    uint64 weight;
    // uint16 delegationFeeBips;
    uint64 minimumStakeDuration;
    uint64 uptimeSeconds;
    uint256 redeemableValidatorRewards;
  }


  /// @custom:storage-location erc7201:gogopool.storage.StakingManagerStorage
  struct StakingManagerStorage {
    /// @notice The ERC20 token used for staking. address(0) for native.
    IERC20Mintable token;
    /// @notice The minimum amount of stake required to be a validator.
    uint256 minimumStakeAmount;
    /// @notice The maximum amount of stake allowed to be a validator.
    uint256 maximumStakeAmount;
    /// @notice The minimum amount of time in seconds a validator must be staked for. Must be at least {churnPeriodSeconds}.
    uint64 minimumStakeDuration;
    /// @notice The ID of the blockchain that submits uptime proofs. This must be a blockchain validated by the l1ID that this contract manages.
    bytes32 uptimeBlockchainID;

    /// @notice The reward calculator for this validator manager.
    IRewardCalculator rewardCalculator;

    /// @notice Address of the PoAValidatorManager contract.
    IPoAValidatorManager validatorManager;

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

  function initialize(IPoAValidatorManager validatorManager) public initializer {
    StakingManagerStorage storage $ = _getStorage();
    $.validatorManager = validatorManager;
    // TODO settings
    $.token = IERC20Mintable(address(0));
    $.minimumStakeAmount = 100;
    $.maximumStakeAmount = 1000000;
    $.minimumStakeDuration = 1000;
    __Ownable_init(msg.sender);
    __UUPSUpgradeable_init();
  }

  function initializeStake(StakingInput calldata input) payable external returns (bytes32) {
    StakingManagerStorage storage $ = _getStorage();

    _lockStake(input);

    address owner = input.owner;
    if (owner == address(0)) {
      owner = _msgSender();
    }


    if (input.minimumStakeDuration < $.minimumStakeDuration) {
      revert InvalidMinStakeDuration(input.minimumStakeDuration);
    }
    if (input.amount < $.minimumStakeAmount || input.amount > $.maximumStakeAmount) {
      revert InvalidStakeAmount(input.amount);
    }

    uint64 weight = valueToWeight(input.amount);
    bytes32 validationID = $.validatorManager.initializeValidatorRegistration(input.input, weight);

    $.validatorInfo[validationID].owner = owner;
    $.validatorInfo[validationID].tokenAddress = input.tokenAddress;
    $.validatorInfo[validationID].amount = input.amount;
    $.validatorInfo[validationID].weight = weight;
    $.validatorInfo[validationID].minimumStakeDuration = input.minimumStakeDuration;

    return validationID;
  }

  function _lockStake(StakingInput calldata input) internal {
    StakingManagerStorage storage $ = _getStorage();
    // Native token or ERC20
    if (input.tokenAddress == address(0)) { 
      require(msg.value == input.amount, "Incorrect amount sent");
    } else {
      require(address($.token) == input.tokenAddress, "Invalid token address");
      $.token.transferFrom(input.owner, address(this), input.amount);
    }
  }

  function _unlockStake(bytes32 validationID) internal {
    StakingManagerStorage storage $ = _getStorage();
    if ($.validatorInfo[validationID].tokenAddress == address(0)) { 
      payable($.validatorInfo[validationID].owner).transfer($.validatorInfo[validationID].amount);
    } else {
      $.token.transfer($.validatorInfo[validationID].owner, $.validatorInfo[validationID].amount);
    }
  }

  function _withdrawRewards(bytes32 validationID) internal {
    StakingManagerStorage storage $ = _getStorage();
    uint256 rewards = $.validatorInfo[validationID].redeemableValidatorRewards;
    $.validatorInfo[validationID].redeemableValidatorRewards = 0;
    if ($.validatorInfo[validationID].tokenAddress == address(0)) { 
      
    } else {

    }
  }

  function completeStake(uint32 messageIndex) external {
    StakingManagerStorage storage $ = _getStorage();
    $.validatorManager.completeValidatorRegistration(messageIndex);
  }
  
  function initializeUnstake(
    bytes32 validationID,
    bool includeUptimeProof,
    uint32 messageIndex
  ) external returns (bool) {
    StakingManagerStorage storage $ = _getStorage();
    Validator memory validator = $.validatorManager.initializeEndValidation(validationID);
    
    // PoS validations can only be ended by their owners.
    if ($.validatorInfo[validationID].owner != _msgSender()) {
      revert UnauthorizedOwner(_msgSender());
    }

    // Check that minimum stake duration has passed.
    if (validator.endedAt < validator.startedAt + $.validatorInfo[validationID].minimumStakeDuration) {
      revert MinStakeDurationNotPassed(validator.endedAt);
    }

    // Uptime proofs include the absolute number of seconds the validator has been active.
    uint64 uptimeSeconds;
    if (includeUptimeProof) {
      uptimeSeconds = _updateUptime(validationID, messageIndex);
    } else {
      uptimeSeconds = $.validatorInfo[validationID].uptimeSeconds;
    }

    uint256 reward = $.rewardCalculator.calculateReward({
        stakeAmount: $.validatorInfo[validationID].amount,
        validatorStartTime: validator.startedAt,
        stakingStartTime: validator.startedAt,
        stakingEndTime: validator.endedAt,
        uptimeSeconds: uptimeSeconds
    });

    $.validatorInfo[validationID].redeemableValidatorRewards += reward;
    // $._rewardRecipients[validationID] = rewardRecipient;

    return (reward > 0);
  }

  function completeUnstake(uint32 messageIndex) external {
    StakingManagerStorage storage $ = _getStorage();
    (bytes32 validationID, Validator memory validator) = $.validatorManager.completeEndValidation(messageIndex);
    // The validator can either be Completed or Invalidated here. We only grant rewards for Completed.
    if (validator.status == ValidatorStatus.Completed) {
      uint256 rewards = $.validatorInfo[validationID].redeemableValidatorRewards;
      $.validatorInfo[validationID].redeemableValidatorRewards = 0;
      $.token.transfer($.validatorInfo[validationID].owner, rewards);
    }
    _unlockStake(validationID);
  }


  function valueToWeight(uint256 value) public view returns (uint64) {
    // TODO maybe move this out to a rewardsCalc-like contract?
    uint256 weight = value / 1;
    if (weight == 0 || weight > type(uint64).max) {
      revert InvalidStakeAmount(value);
    }
    return uint64(weight);
  }



  function _updateUptime(bytes32 validationID, uint32 messageIndex) internal returns (uint64) {
      (WarpMessage memory warpMessage, bool valid) =
          WARP_MESSENGER.getVerifiedWarpMessage(messageIndex);
      if (!valid) {
          revert InvalidWarpMessage();
      }

    StakingManagerStorage storage $ = _getStorage();
      // The uptime proof must be from the specifed uptime blockchain
      if (warpMessage.sourceChainID != $.uptimeBlockchainID) {
          revert InvalidWarpSourceChainID(warpMessage.sourceChainID);
      }

      // The sender is required to be the zero address so that we know the validator node
      // signed the proof directly, rather than as an arbitrary on-chain message
      if (warpMessage.originSenderAddress != address(0)) {
          revert InvalidWarpOriginSenderAddress(warpMessage.originSenderAddress);
      }

      (bytes32 uptimeValidationID, uint64 uptime) =
          ValidatorMessages.unpackValidationUptimeMessage(warpMessage.payload);
      if (validationID != uptimeValidationID) {
          revert InvalidValidationID(validationID);
      }

      if (uptime > $.validatorInfo[validationID].uptimeSeconds) {
          $.validatorInfo[validationID].uptimeSeconds = uptime;
          emit UptimeUpdated(validationID, uptime);
      } else {
          uptime = $.validatorInfo[validationID].uptimeSeconds;
      }

      return uptime;
  }


  // Add authorization for upgrades
  function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}