// SPDX-License-Identifier: Ecosystem

pragma solidity 0.8.25;

import "@openzeppelin/contracts-upgradeable/metatx/ERC2771ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ValidatorRegistrationInput, ConversionData, PChainOwner} from "@avalabs/icm-contracts/validator-manager/interfaces/IValidatorManager.sol";
import {INativeSendAndCallReceiver} from "@avalabs/icm-contracts/ictt/interfaces/INativeSendAndCallReceiver.sol";
import {IACP99ValidatorManager} from "../interfaces/IACP99ValidatorManager.sol";

struct StakingInput {
  address staker;
  uint256 amount;
  ValidatorRegistrationInput input;
}

contract StakingManager is UUPSUpgradeable, OwnableUpgradeable, INativeSendAndCallReceiver {

  struct Storage {
    IACP99ValidatorManager validatorManager;
  }

  // keccak256(abi.encode(uint256(keccak256("avalanche-icm.storage.StakingManager")) - 1)) & ~bytes32(uint256(0xff));
  bytes32 public constant STORAGE_LOCATION = 0x81773fca73a14ca21edf1cadc6ec0b26d6a44966f6e97607e90422658d423500;

  function _getStorage() private pure returns (Storage storage $) {
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
    __Ownable_init(msg.sender);
    __UUPSUpgradeable_init();
  }

  function stakeItDude(StakingInput memory stakingInput) payable public {
    require(msg.value > 0 && msg.value == stakingInput.amount, "Invalid amount");
    Storage storage $ = _getStorage();
    bytes32 validationID = $.validatorManager.initializeValidatorRegistration(stakingInput.input, 0);
  }

  // This would be called by the TeleporterMessenger on the L1
  // from INativeSendAndCallReceiver
  function receiveTokens(
    bytes32 sourceBlockchainID,
    address originTokenTransferrerAddress,
    address originSenderAddress,
    bytes calldata payload
  ) external payable {
    StakingInput memory stakingInput = abi.decode(payload, (StakingInput));
    // TODO Verify blockchainID and originTokenTransferrerAddress
    
    // Do we care? Or can anyone stake for any address?
    require(originSenderAddress == stakingInput.staker, "Invalid sender");
    
    stakeItDude(stakingInput);
  }

  // Add authorization for upgrades
  function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}