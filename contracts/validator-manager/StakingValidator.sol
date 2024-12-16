// SPDX-License-Identifier: Ecosystem

pragma solidity 0.8.25;

import {IStakingManager, StakingInput} from "../interfaces/IStakingManager.sol";

// TODO make this follow pattern of upgradeable plus Storage slot
contract StakingValidator {

  struct NFTData {
    uint64 weight;
    bool locked;
  }

  /// @notice Mapping of _keyFrom(nftAddress, nftId) to a defined weight. 
  ///         nftId=0 signifies the default weight for the NFT address.
  ///         If a different weight is specified for the nftId then that weight is used instead of the default.
  mapping(bytes32 nftAddrAndId => NFTData) nftData;


  function validateStakeInput(StakingInput calldata input) external view returns (uint64) {
    return 100;
  }

   /// @dev Constructs a bytes32 key from nftAddress and nftId.
  function _keyFrom(address nftAddress, uint256 nftId) internal pure returns (bytes32) {
    return keccak256(abi.encode(nftAddress, nftId));
  }
 
}
