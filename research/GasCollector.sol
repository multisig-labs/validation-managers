// SPDX-License-Identifier: MIT

pragma solidity ^0.8.25;

import { Address } from "@openzeppelin-contracts-5.2.0/utils/Address.sol";
import { AccessControlUpgradeable } from
  "@openzeppelin-contracts-upgradeable-5.2.0/access/AccessControlUpgradeable.sol";
import { Initializable } from
  "@openzeppelin-contracts-upgradeable-5.2.0/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from
  "@openzeppelin-contracts-upgradeable-5.2.0/proxy/utils/UUPSUpgradeable.sol";

// GasCollector will recieve all gas fees collected on the L1

// TODO figure out best most flexible way to structure roles and perms
// TODO will this work? Not sure how proxies etc work as a destination for the gas fees precompile.
// Maybe just use an EOA? Is this contract necessary?
contract GasCollector is Initializable, AccessControlUpgradeable, UUPSUpgradeable {
  using Address for address payable;

  bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

  event GasFeesWithdrawn(uint256 amount);

  constructor() {
    _disableInitializers();
  }

  function initialize(address defaultAdmin, address upgrader) public initializer {
    __AccessControl_init();
    __UUPSUpgradeable_init();

    _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
    _grantRole(UPGRADER_ROLE, upgrader);
  }

  function withdraw() public onlyRole(DEFAULT_ADMIN_ROLE) {
    payable(msg.sender).sendValue(address(this).balance);
    emit GasFeesWithdrawn(address(this).balance);
  }

  function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) { }
}
