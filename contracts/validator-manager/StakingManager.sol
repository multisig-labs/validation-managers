// SPDX-License-Identifier: Ecosystem

pragma solidity 0.8.25;

import "@openzeppelin/contracts-upgradeable/metatx/ERC2771ContextUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ValidatorRegistrationInput, ConversionData, PChainOwner, ValidatorStatus} from "@avalabs/icm-contracts/validator-manager/interfaces/IValidatorManager.sol";
import {IRewardCalculator} from "@avalabs/icm-contracts/validator-manager/interfaces/IRewardCalculator.sol";
import {ValidatorMessages} from "@avalabs/icm-contracts/validator-manager/ValidatorMessages.sol";
import {INativeSendAndCallReceiver} from "@avalabs/icm-contracts/ictt/interfaces/INativeSendAndCallReceiver.sol";
import {IWarpMessenger, WarpMessage} from "@avalabs/subnet-evm-contracts/contracts/interfaces/IWarpMessenger.sol";
import {IACP99ValidatorManager} from "../interfaces/IACP99ValidatorManager.sol";
import {IStakingManager, StakingInputNFT, StakingInputToken} from "../interfaces/IStakingManager.sol";
import {ICertificate} from "../interfaces/ICertificate.sol";


// TODO https://eips.ethereum.org/EIPS/eip-5753 for locking NFTs?
// https://eips.ethereum.org/EIPS/eip-5633


contract StakingManager is IStakingManager, UUPSUpgradeable, OwnableUpgradeable, INativeSendAndCallReceiver {

  struct NFTData {
    uint64 weight;
    bool locked;
  }

  struct ValidatorInfo {
    address owner;
    bytes32 nftAddressAndId;
    address tokenAddress; // address(0) for native
    uint256 amount;
    uint64 weight;
    // uint16 delegationFeeBips;
    uint64 minimumStakeDuration;
    uint64 uptimeSeconds;
  }

  IWarpMessenger public constant WARP_MESSENGER = IWarpMessenger(0x0200000000000000000000000000000000000005);
  bytes32 public constant P_CHAIN_BLOCKCHAIN_ID = bytes32(0);

  error InvalidWarpOriginSenderAddress(address senderAddress);
  error InvalidWarpSourceChainID(bytes32 sourceChainID);
  error InvalidWarpMessage();
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
    /// @notice The maximum amount of time in seconds a validator could be staked for
    uint64 maximumStakeDuration;
    /// @notice The ID of the blockchain that submits uptime proofs. This must be a blockchain validated by the subnetID that this contract manages.
    bytes32 uptimeBlockchainID;
    /// @notice Mapping of _keyFrom(nftAddress, nftId) to a defined weight. 
    ///         nftId=0 signifies the default weight for the NFT address.
    ///         If a different weight is specified for the nftId then that weight is used instead of the default.
    mapping(bytes32 nftAddrAndId => NFTData) nftData;

    /// @notice The reward calculator for this validator manager.
    IRewardCalculator rewardCalculator;

    /// @notice Address of the Certificate NFT contract that holds KYC certs, etc.
    ICertificate certificateNFTAddress;
    /// @notice Address of the ValidatorManager contract.
    IACP99ValidatorManager validatorManager;

    /// @notice Maps the validation ID to its requirements.
    mapping(bytes32 validationID => ValidatorInfo) validatorInfo;
  }


  event UptimeUpdated(bytes32 indexed validationID, uint64 uptime);
  
  error InvalidNFTAddress(address nftAddress);
  error InvalidLicense(address nftAddress, uint256 nftId);
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

  function initialize(IACP99ValidatorManager validatorManager) public initializer {
    Storage storage $ = _getStorage();
    $.validatorManager = validatorManager;
    // TODO settings
    $.minimumStakeAmount = 100;
    $.maximumStakeAmount = 1000000;
    $.minimumStakeDuration = 1000;
    $.maximumStakeDuration = 1000000;
    $.uptimeBlockchainID = bytes32(keccak256("test_chain"));
    __Ownable_init(msg.sender);
    __UUPSUpgradeable_init();
  }

  function initializeStake(StakingInput calldata input) payable external returns (bytes32) {
    Storage storage $ = _getStorage();
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
    $.validatorInfo[validationID].uptimeSeconds = 0;    

    return validationID;
  }

  // External fn that either reverts if anything is wrong, or returns a weight.
  function validateStakeInput(StakingInput calldata input) internal view returns (uint64) {

  }

  function initializeStakeNFT(StakingInputNFT calldata input) external returns (bytes32) {
    Storage storage $ = _getStorage();
    if (validateLicense(input.nftAddress, input.nftId) == false) {
      revert InvalidLicense(input.nftAddress, input.nftId);
    }

    address owner = _msgSender();
    if (validateValidator(owner) == false) {
      revert InvalidValidator(owner);
    }

    _lockNFT(owner, input.nftAddress, input.nftId);
    uint64 weight = licenseToWeight(input.nftAddress, input.nftId);
    bytes32 validationID = $.validatorManager.initializeValidatorRegistration(input.input, weight);

    $.validatorInfo[validationID].owner = owner;
    $.validatorInfo[validationID].nftAddressAndId = _keyFrom(input.nftAddress, input.nftId);
    $.validatorInfo[validationID].weight = weight;
    $.validatorInfo[validationID].minimumStakeDuration = input.minimumStakeDuration;
    $.validatorInfo[validationID].uptimeSeconds = 0;

    return validationID;
  }

  function completeStakeNFT(uint32 messageIndex) external returns (bytes32) {
    Storage storage $ = _getStorage();
    return $.validatorManager.completeValidatorRegistration(messageIndex);
  }

  function completeStakeToken(uint32 messageIndex) external returns (bytes32) {
    Storage storage $ = _getStorage();
    return $.validatorManager.completeValidatorRegistration(messageIndex);
  }
  
  // function stakeItDude(StakingInput memory stakingInput) payable public {
  //   require(msg.value > 0 && msg.value == stakingInput.amount, "Invalid amount");
  //   Storage storage $ = _getStorage();
  //   bytes32 validationID = $.validatorManager.initializeValidatorRegistration(stakingInput.input, 0);
  // }


  /// @notice Check if user holds whatever required NFT Certificates (KYC, etc)
  // TODO make this more dynamic. Also maybe just validate on reward claim?
  function validateValidator(address user) public view returns (bool) {
    Storage storage $ = _getStorage();
    if (address($.certificateNFTAddress) == address(0)) {
      return true;
    }
    uint256 tokenId = $.certificateNFTAddress.tokenByCollection(user, keccak256("KYC"));
    return tokenId > 0;
  }

  /// @notice Check if user holds whatever required NFT Certificates (KYC, etc)
  function validateDelegator(address user) public view returns (bool) {
    // In this example anyone can delegate.
    return true;
  }

  /// @notice Check if this NFT is allowed to be used as a license, and has not been used already..
  // TODO maybe combine with licenseToWeight and just check for > 0 to be valid?
  function validateLicense(address nftAddress, uint256 nftId) public view returns (bool) {
    Storage storage $ = _getStorage();
    return nftId > 0 &&licenseToWeight(nftAddress, nftId) > 0 && $.lockedNFTs[_keyFrom(nftAddress, nftId)] == false;
  }

  // TODO Maybe move this out to a rewardsCalc-like contract?
  /// @notice Returns the weight associated with an NFT, first checking if a specific weight is set, otherwise default.
  function licenseToWeight(address nftAddress, uint256 nftId) public view returns (uint64) {
    Storage storage $ = _getStorage();
    // Returns static values, but could be dynamic if we wanted to determine the weight of an NFT by some algorithm.
    uint64 defaultWeight = $.nftWeights[_keyFrom(nftAddress, uint256(0))];
    uint64 idWeight = $.nftWeights[_keyFrom(nftAddress, nftId)];
    return (idWeight > 0) ? idWeight : defaultWeight;
  }

  function valueToWeight(uint256 value) public view returns (uint64) {
    // TODO maybe move this out to a rewardsCalc-like contract?
    uint256 weight = value / 1;
    if (weight == 0 || weight > type(uint64).max) {
        revert InvalidStakeAmount(value);
    }
    return uint64(weight);
  }

  function submitUptimeProof(bytes32 validationID, uint32 messageIndex) external {
    // if (!_isPoSValidator(validationID)) {
    //   revert ValidatorNotPoS(validationID);
    // }
    Storage storage $ = _getStorage();
    ValidatorStatus status = $.validatorManager.getValidator(validationID).status;
    if (status != ValidatorStatus.Active) {
      revert InvalidValidatorStatus(status);
    }

    // Uptime proofs include the absolute number of seconds the validator has been active.
    _updateUptime(validationID, messageIndex);
  }

  function _updateUptime(bytes32 validationID, uint32 messageIndex) internal returns (uint64) {
    (WarpMessage memory warpMessage, bool valid) = WARP_MESSENGER.getVerifiedWarpMessage(messageIndex);
    if (!valid) {
      revert InvalidWarpMessage();
    }

    Storage storage $ = _getStorage();
    // The uptime proof must be from the specifed uptime blockchain
    if (warpMessage.sourceChainID != $.uptimeBlockchainID) {
      revert InvalidWarpSourceChainID(warpMessage.sourceChainID);
    }

    // The sender is required to be the zero address so that we know the validator node
    // signed the proof directly, rather than as an arbitrary on-chain message
    if (warpMessage.originSenderAddress != address(0)) {
      revert InvalidWarpOriginSenderAddress(warpMessage.originSenderAddress);
    }

    (bytes32 uptimeValidationID, uint64 uptime) = ValidatorMessages.unpackValidationUptimeMessage(warpMessage.payload);
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

  // This would be called by the TeleporterMessenger on the L1
  // from INativeSendAndCallReceiver
  function receiveTokens(
    bytes32 sourceBlockchainID,
    address originTokenTransferrerAddress,
    address originSenderAddress,
    bytes calldata payload
  ) external payable {
    // StakingInput memory stakingInput = abi.decode(payload, (StakingInput));
    // // TODO Verify blockchainID and originTokenTransferrerAddress
    
    // // Do we care? Or can anyone stake for any address?
    // require(originSenderAddress == stakingInput.staker, "Invalid sender");
    
    // stakeItDude(stakingInput);
  }

  function _lock(uint256 amount) internal returns (uint256) {
    // TODO maybe use inheritance? 
    return amount;
  }

  function _lockNFT(address owner, address nftAddress, uint256 nftId) internal {
    Storage storage $ = _getStorage();
    $.lockedNFTs[_keyFrom(nftAddress, nftId)] = true;
  }

  /// @dev Constructs a bytes32 key from nftAddress and nftId.
  function _keyFrom(address nftAddress, uint256 nftId) internal pure returns (bytes32) {
    return keccak256(abi.encode(nftAddress, nftId));
  }

  // Used for delegation stuff
  function _getPChainWarpMessage(uint32 messageIndex) internal view returns (WarpMessage memory) {
    (WarpMessage memory warpMessage, bool valid) = WARP_MESSENGER.getVerifiedWarpMessage(messageIndex);
    if (!valid) {
      revert InvalidWarpMessage();
    }
    // Must match to P-Chain blockchain id, which is 0.
    if (warpMessage.sourceChainID != P_CHAIN_BLOCKCHAIN_ID) {
      revert InvalidWarpSourceChainID(warpMessage.sourceChainID);
    }
    if (warpMessage.originSenderAddress != address(0)) {
      revert InvalidWarpOriginSenderAddress(warpMessage.originSenderAddress);
    }

    return warpMessage;
  }

  // Add authorization for upgrades
  function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}