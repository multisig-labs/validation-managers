// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

import { INFTStakingManager } from "../../contracts/tokens/NodeLicense.sol";

contract MockStakingManager is INFTStakingManager {
  mapping(uint256 => bytes32) private _lockedTokens;

  function setTokenLocked(uint256 tokenId, bytes32 lockId) external {
    _lockedTokens[tokenId] = lockId;
  }

  function clearTokenLock(uint256 tokenId) external {
    delete _lockedTokens[tokenId];
  }

  function getTokenLockedBy(uint256 tokenId) external view returns (bytes32) {
    return _lockedTokens[tokenId];
  }
}
