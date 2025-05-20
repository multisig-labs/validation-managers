// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

// https://github.com/OpenZeppelin/openzeppelin-contracts/issues/4791#issuecomment-1849977413

abstract contract ERC2771ContextStorage {
  bytes32 public constant ERC2771_CONTEXT_STORAGE_POSITION = keccak256("erc2771.context.storage");

  function trustedForwarder() public view returns (address operator) {
    bytes32 position = ERC2771_CONTEXT_STORAGE_POSITION;
    assembly {
      operator := sload(position)
    }
  }

  /**
   * @dev Indicates whether any particular address is the trusted forwarder.
   */
  function isTrustedForwarder(address operator) public view returns (bool) {
    return operator == trustedForwarder();
  }

  // @dev Set the trusted forwarder address. Parent contract must apply appropriate access control.
  function _setTrustedForwarder(address operator) internal virtual {
    bytes32 position = ERC2771_CONTEXT_STORAGE_POSITION;
    assembly {
      sstore(position, operator)
    }
  }

  /**
   * @dev Override for `msg.sender`. Defaults to the original `msg.sender` whenever
   * a call is not performed by the trusted forwarder or the calldata length is less than
   * 20 bytes (an address length).
   */
  function _msgSender() internal view virtual returns (address) {
    uint256 calldataLength = msg.data.length;
    uint256 contextSuffixLength = 20;
    if (isTrustedForwarder(msg.sender) && calldataLength >= contextSuffixLength) {
      return address(bytes20(msg.data[calldataLength - contextSuffixLength:]));
    } else {
      return msg.sender;
    }
  }

  /**
   * @dev Override for `msg.data`. Defaults to the original `msg.data` whenever
   * a call is not performed by the trusted forwarder or the calldata length is less than
   * 20 bytes (an address length).
   */
  function _msgData() internal view virtual returns (bytes calldata) {
    uint256 calldataLength = msg.data.length;
    uint256 contextSuffixLength = 20;
    if (isTrustedForwarder(msg.sender) && calldataLength >= contextSuffixLength) {
      return msg.data[:calldataLength - contextSuffixLength];
    } else {
      return msg.data;
    }
  }
}
