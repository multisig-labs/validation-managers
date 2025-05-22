// SPDX-License-Identifier: MIT

pragma solidity ^0.8.25;

import { ERC2771ContextStorage } from "../utils/ERC2771ContextStorage.sol";
import { NodeLicense, NodeLicenseSettings } from "./NodeLicense.sol";
import { ContextUpgradeable } from
  "@openzeppelin-contracts-upgradeable-5.3.0/utils/ContextUpgradeable.sol";

contract NodeLicenseGasless is NodeLicense, ERC2771ContextStorage {
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize(NodeLicenseSettings memory settings, address trustedForwarder)
    public
    initializer
  {
    super.initialize(settings);
    _setTrustedForwarder(trustedForwarder);
  }

  function setTrustedForwarder(address _trustedForwarder) public onlyRole(DEFAULT_ADMIN_ROLE) {
    _setTrustedForwarder(_trustedForwarder);
  }

  function _msgSender()
    internal
    view
    override (ContextUpgradeable, ERC2771ContextStorage)
    returns (address sender)
  {
    return ERC2771ContextStorage._msgSender();
  }

  function _msgData()
    internal
    view
    override (ContextUpgradeable, ERC2771ContextStorage)
    returns (bytes calldata data)
  {
    return ERC2771ContextStorage._msgData();
  }
}
