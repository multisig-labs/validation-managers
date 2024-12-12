// SPDX-License-Identifier: Ecosystem

pragma solidity 0.8.25;

import {ExampleRewardCalculator} from "@avalabs/icm-contracts/validator-manager/ExampleRewardCalculator.sol";
import {ValidatorManager} from "@avalabs/icm-contracts/validator-manager/ValidatorManager.sol";
import {ValidatorMessages} from "@avalabs/icm-contracts/validator-manager/ValidatorMessages.sol";
import {
  ConversionData,
  IValidatorManager,
  InitialValidator,
  PChainOwner,
  Validator,
  ValidatorManagerSettings,
  ValidatorRegistrationInput,
  ValidatorStatus
} from "@avalabs/icm-contracts/validator-manager/interfaces/IValidatorManager.sol";
import {IWarpMessenger, WarpMessage} from "@avalabs/subnet-evm-contracts/contracts/interfaces/IWarpMessenger.sol";

import {INativeMinter} from "@avalabs/subnet-evm-contracts/contracts/interfaces/INativeMinter.sol";
import {ICMInitializable} from "@avalabs/icm-contracts/utilities/ICMInitializable.sol";

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import {INFTStakingManager, NFTValidatorManagerSettings, NFTValidatorInfo} from "../interfaces/INFTStakingManager.sol";
import {ValidatorReceipt} from "../tokens/ValidatorReceipt.sol";
import {INFTLicenseModule} from "../interfaces/INFTLicenseModule.sol";

contract NFTStakingManager is INFTStakingManager, ValidatorManager, OwnableUpgradeable, ReentrancyGuardUpgradeable {
  using Address for address payable;

  INativeMinter public constant NATIVE_MINTER = INativeMinter(0x0200000000000000000000000000000000000001);

  /// @custom:storage-location erc7201:gogopool.storage.NFTStakingManagerStorage
  struct NFTStakingManagerStorage {
    INFTLicenseModule _licenseModule;
    /// @notice The address of the validator receipt NFT contract
    address _validatorReceiptAddress;
    /// @notice The blockchain ID of the uptime blockchain
    bytes32 _uptimeBlockchainID;

    mapping(bytes32 validationID => NFTValidatorInfo) _nftValidatorInfo;
    mapping(uint256 receiptId => bytes32 validationID) _receiptToValidation;
  }

  // keccak256(abi.encode(uint256(keccak256("gogopool.storage.NFTStakingManagerStorage")) - 1)) & ~bytes32(uint256(0xff));
  bytes32 public constant NFT_STAKING_MANAGER_STORAGE_LOCATION = 0xb2bea876b5813e5069ed55d22ad257d01245c883a221b987791b00df2f4dfa00;

  event UptimeUpdated(bytes32 indexed validationID, uint64 uptime);

  error InvalidNFTAddress(address nftAddress);
  error InvalidLicense(address nftAddress, uint256 nftId);
  error InvalidValidator(address validator);
  error InvalidReceipt(uint256 receiptId, address receiptOwner);

  function _getNFTStakingManagerStorage() private pure returns (NFTStakingManagerStorage storage $) {
    // solhint-disable-next-line no-inline-assembly
    assembly {
      $.slot := NFT_STAKING_MANAGER_STORAGE_LOCATION
    }
  }

  constructor(ICMInitializable init) {
    if (init == ICMInitializable.Disallowed) {
      _disableInitializers();
    }
  }

  function initialize(NFTValidatorManagerSettings calldata settings, address initialOwner) external initializer {
    __NFTStakingManager_init(settings, initialOwner);
  }

  function __NFTStakingManager_init(NFTValidatorManagerSettings calldata settings, address initialOwner) internal
        onlyInitializing {
    __ValidatorManager_init(settings.baseSettings);
    __Ownable_init(initialOwner);
    __ReentrancyGuard_init();
    __NFTStakingManager_init_unchained(settings);
  }


  function __NFTStakingManager_init_unchained(NFTValidatorManagerSettings calldata settings) internal onlyInitializing {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    $._licenseModule = settings.licenseModule;
    $._uptimeBlockchainID = settings.uptimeBlockchainID;
    $._validatorReceiptAddress = settings.validatorReceiptAddress;
  }

  function initializeValidatorRegistration(ValidatorRegistrationInput calldata registrationInput, address nftAddress, uint256 nftId)
    external
    nonReentrant
    returns (bytes32 validationID)
  {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    if ($._licenseModule.validateLicense(nftAddress, nftId) == false) {
      revert InvalidLicense(nftAddress, nftId);
    }
    if ($._licenseModule.validateValidator(_msgSender()) == false) {
      revert InvalidValidator(_msgSender());
    }
    uint256 receiptId = _lockAndIsssueReceipt(_msgSender(), nftAddress, nftId);
    NFTValidatorInfo memory info = NFTValidatorInfo({nftAddress: nftAddress, nftId: nftId, receiptId: receiptId, uptimeSeconds: 0, redeemableValidatorRewards: 0});
    uint64 weight = $._licenseModule.licenseToWeight(nftAddress, nftId);
    validationID = _initializeValidatorRegistration(registrationInput, weight);
    $._nftValidatorInfo[validationID] = info;
    $._receiptToValidation[receiptId] = validationID;
  }

  function initializeEndValidation(bytes32 validationID, bool includeUptimeProof, uint32 messageIndex) external {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    NFTValidatorInfo storage info = $._nftValidatorInfo[validationID];
    
    address receiptOwner = ValidatorReceipt($._validatorReceiptAddress).ownerOf(info.receiptId);
    if (receiptOwner != _msgSender()) {
      revert InvalidReceipt(info.receiptId, receiptOwner);
    }
    
    Validator memory validator = _initializeEndValidation(validationID);

    // Uptime proofs include the absolute number of seconds the validator has been active.
    uint64 uptimeSeconds;
    if (includeUptimeProof) {
      uptimeSeconds = _updateUptime(validationID, messageIndex);
    } else {
      uptimeSeconds = info.uptimeSeconds;
    }

    uint256 reward = $._licenseModule.calculateReward({
      nftAddress: info.nftAddress,
      nftId: info.nftId,
      validatorStartTime: validator.startedAt,
      stakingStartTime: validator.startedAt,
      stakingEndTime: validator.endedAt,
      uptimeSeconds: uptimeSeconds
    });
    info.redeemableValidatorRewards += reward; 
  }

  function completeEndValidation(uint32 messageIndex) external {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    (bytes32 validationID, ) = _completeEndValidation(messageIndex);
    uint256 receiptId = $._nftValidatorInfo[validationID].receiptId;
    address receiptOwner = ValidatorReceipt($._validatorReceiptAddress).ownerOf(receiptId);
    _unlockAndPayRewards(receiptOwner, receiptId);
    delete $._nftValidatorInfo[validationID];
    delete $._receiptToValidation[receiptId];
  }

  function _lockAndIsssueReceipt(address from, address nftAddress, uint256 nftId) internal returns (uint256 receiptId) {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    IERC721(nftAddress).safeTransferFrom(from, address(this), nftId);
    receiptId = ValidatorReceipt($._validatorReceiptAddress).mint(from);
  }

  function _unlockAndPayRewards(address to, uint256 receiptId) internal nonReentrant {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    bytes32 validationID = $._receiptToValidation[receiptId];
    NFTValidatorInfo memory info = $._nftValidatorInfo[validationID];

    IERC721(info.nftAddress).safeTransferFrom(address(this), to, info.nftId);
    ValidatorReceipt($._validatorReceiptAddress).burn(receiptId);
    NATIVE_MINTER.mintNativeCoin(to, info.redeemableValidatorRewards);
  }

  function submitUptimeProof(bytes32 validationID, uint32 messageIndex) external {
      ValidatorStatus status = getValidator(validationID).status;
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

    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();

    // The uptime proof must be from the specifed uptime blockchain
    if (warpMessage.sourceChainID != $._uptimeBlockchainID) {
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

    if (uptime > $._nftValidatorInfo[validationID].uptimeSeconds) {
      $._nftValidatorInfo[validationID].uptimeSeconds = uptime;
      emit UptimeUpdated(validationID, uptime);
    } else {
      uptime = $._nftValidatorInfo[validationID].uptimeSeconds;
    }

    return uptime;
  }

  function getValidatorInfo(bytes32 validationID) external view returns (NFTValidatorInfo memory) {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    return $._nftValidatorInfo[validationID];
  }

  function getReceiptToValidation(uint256 receiptId) external view returns (bytes32) {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    return $._receiptToValidation[receiptId];
  }

  // Required function to receive ERC-721 tokens safely
  function onERC721Received(address, /*operator*/ address, /*from*/ uint256, /* tokenId */ bytes calldata /*data*/ ) external pure returns (bytes4) {
    return this.onERC721Received.selector;
  }
}
