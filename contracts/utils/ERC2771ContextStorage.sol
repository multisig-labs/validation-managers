// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { ERC2771ContextUpgradeable } from
  "@openzeppelin-contracts-upgradeable-5.3.0/metatx/ERC2771ContextUpgradeable.sol";

// https://github.com/OpenZeppelin/openzeppelin-contracts/issues/4791#issuecomment-1849977413

abstract contract ERC2771ContextStorage is ERC2771ContextUpgradeable(address(0)) {
  bytes32 public constant ERC2771_CONTEXT_STORAGE_POSITION = keccak256("erc2771.context.storage");

  // @dev Set the trusted forwarder address. Must apply appropriate access control.
  function setTrustedForwarder(address operator) public {
    bytes32 position = ERC2771_CONTEXT_STORAGE_POSITION;
    assembly {
      sstore(position, operator)
    }
  }

  function trustedForwarder() public view override returns (address operator) {
    bytes32 position = ERC2771_CONTEXT_STORAGE_POSITION;
    assembly {
      operator := sload(position)
    }
  }

  /**
   * @dev Indicates whether any particular address is the trusted forwarder.
   */
  function isTrustedForwarder(address forwarder) public view override returns (bool) {
    return forwarder == trustedForwarder();
  }

  /**
   * @dev Override for `msg.sender`. Defaults to the original `msg.sender` whenever
   * a call is not performed by the trusted forwarder or the calldata length is less than
   * 20 bytes (an address length).
   */
  function _msgSender() internal view virtual override returns (address) {
    return super._msgSender();
  }

  /**
   * @dev Override for `msg.data`. Defaults to the original `msg.data` whenever
   * a call is not performed by the trusted forwarder or the calldata length is less than
   * 20 bytes (an address length).
   */
  function _msgData() internal view virtual override returns (bytes calldata) {
    return super._msgData();
  }

  /**
   * @dev ERC-2771 specifies the context as being a single address (20 bytes).
   */
  function _contextSuffixLength() internal view virtual override returns (uint256) {
    return 20;
  }
}
