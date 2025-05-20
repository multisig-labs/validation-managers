// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { NFTStakingManager, NFTStakingManagerSettings } from "./NFTStakingManager.sol";
import { ERC2771ContextStorage } from "./utils/ERC2771ContextStorage.sol";
import { ContextUpgradeable } from
  "@openzeppelin-contracts-upgradeable-5.3.0/utils/ContextUpgradeable.sol";

contract NFTStakingManagerGasless is NFTStakingManager, ERC2771ContextStorage {
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize(NFTStakingManagerSettings calldata settings, address trustedForwarder)
    external
    initializer
  {
    super.initialize(settings);
    setTrustedForwarder(trustedForwarder);
  }

  function _msgSender()
    internal
    view
    override (ContextUpgradeable, ERC2771ContextStorage)
    returns (address)
  {
    return ERC2771ContextStorage._msgSender();
  }

  function _msgData()
    internal
    view
    override (ContextUpgradeable, ERC2771ContextStorage)
    returns (bytes calldata)
  {
    return ERC2771ContextStorage._msgData();
  }
}
