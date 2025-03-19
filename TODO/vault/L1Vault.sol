// SPDX-License-Identifier: Ecosystem

pragma solidity 0.8.25;

import {AccessControlDefaultAdminRulesUpgradeable} from
  "@openzeppelin-contracts-upgradeable-5.2.0/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import {AccessControlEnumerableUpgradeable} from "@openzeppelin-contracts-upgradeable-5.2.0/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin-contracts-upgradeable-5.2.0/access/extensions/AccessControlUpgradeable.sol";
import {Initializable} from "@openzeppelin-contracts-upgradeable-5.2.0/proxy/utils/Initializable.sol";

contract L1Vault is Initializable, AccessControlUpgradeable, AccessControlDefaultAdminRulesUpgradeable, AccessControlEnumerableUpgradeable {
  bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

  struct L1VaultStorage {
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

  function initialize(address defaultAdmin, address upgrader) public initializer {
    __AccessControl_init();
    __UUPSUpgradeable_init();

    _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
    _grantRole(UPGRADER_ROLE, upgrader);

    Storage storage $ = _getStorage();
  }

  function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}

  function depositToken(address token, uint256 amount) external {
    IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
    emit TokenDeposited(token, amount);
    //send to vault
  }
}
