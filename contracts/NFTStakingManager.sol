// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Validator, ValidatorStatus, PChainOwner } from "icm-contracts-8817f47/contracts/validator-manager/ACP99Manager.sol";
import { ValidatorManager } from "icm-contracts-8817f47/contracts/validator-manager/ValidatorManager.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
// import { IWarpMessenger } from "

contract NFTStakingManager {
  error FailedToLockAllNFTs();
  error FailedToUnlockAllNFTs();

  event NFTsUnlocked(address indexed recipient, uint256[] nftIds);

  // keccak256(abi.encode(uint256(keccak256("gogopool.storage.NFTStakingManagerStorage")) - 1)) & ~bytes32(uint256(0xff));
  bytes32 public constant NFT_STAKING_MANAGER_STORAGE_LOCATION =
    0xb2bea876b5813e5069ed55d22ad257d01245c883a221b987791b00df2f4dfa00;

  struct NFTStakingManagerStorage {
    ValidatorManager _manager;
    IERC721 _nftContract;
    mapping(uint256 nftID => bytes32 validationID) nftToValidationId;
    mapping(address owner => uint256 count) nftCounts;
  }

  NFTStakingManagerStorage private _storage;
  
  function initiateValidatorRegistrationOnBehalfOf(
    address owner,
    bytes memory nodeID,
    bytes memory blsPublicKey,
    PChainOwner memory remainingBalanceOwner,
    PChainOwner memory disableOwner,
    uint256[] memory nftIds
  ) public returns (bytes32 validationID) {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();

    uint256 lockedCount = _lockNFTs(nftIds);
    if (lockedCount != nftIds.length) {
      revert FailedToLockAllNFTs();
    }

    // assume weight of 100 for each NFT
    uint64 weight = uint64(nftIds.length * 100);

    bytes32 validationID = $._manager.initiateValidatorRegistration(
      nodeID,
      blsPublicKey,
      uint64(block.timestamp + 1 days),
      remainingBalanceOwner,
      disableOwner,
      weight
    );

    return validationID;

  }

  function initiateValidatorRegistration(
    bytes memory nodeID,
    bytes memory blsPublicKey,
    PChainOwner memory remainingBalanceOwner,
    PChainOwner memory disableOwner,
    uint256[] memory nftIds
  ) external returns (bytes32 validationID) {
    return initiateValidatorRegistrationOnBehalfOf(msg.sender, nodeID, blsPublicKey, remainingBalanceOwner, disableOwner, nftIds);
  }

  function completeValidatorRegistration(uint32 messageIndex) external returns (bytes32) {
    return _getNFTStakingManagerStorage()._manager.completeValidatorRegistration(messageIndex);
  }

  function initiateAddLicenseToValidator(bytes32 validationID, uint256[] memory nftIds) external {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();

    uint256 lockedCount = _lockNFTs(nftIds);
    if (lockedCount != nftIds.length) {
      revert FailedToLockAllNFTs();
    }
    // check that the owners match?

    Validator memory validator = $._manager.getValidator(validationID);
    uint64 weight = uint64(validator.weight + nftIds.length * 100);
    uint64 newWeight = validator.weight + weight;

    $._manager.initiateValidatorWeightUpdate(validationID, newWeight);
  }

  function completeAddLicenseToValidator(uint32 messageIndex) external returns (bytes32, uint64) {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();

    (bytes32 validationID, uint64 nonce) = $._manager.completeValidatorWeightUpdate(messageIndex);

    return (validationID, nonce);
  }

  function initiateRemoveLicenseFromValidator(
    bytes32 validationID,
    uint256[] memory nftIds
  ) external {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    Validator memory validator = $._manager.getValidator(validationID);

    // okay here we want to unlock the NFTs
    uint256 unlockCount = _unlockNFTs(msg.sender, nftIds);
    if (unlockCount != nftIds.length) {
      revert FailedToUnlockAllNFTs();
    }
    
    uint64 newWeight = validator.weight - uint64(nftIds.length * 100);

    $._manager.initiateValidatorWeightUpdate(validationID, newWeight);
  }

  function completeRemoveLicenseFromValidator(uint32 messageIndex) external returns (bytes32, uint64) {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();

    (bytes32 validationID, uint64 nonce) = $._manager.completeValidatorWeightUpdate(messageIndex);

    return (validationID, nonce);
  }

  function getNFTCount(address owner) external view returns (uint256) {
    return _getNFTStakingManagerStorage().nftCounts[owner];
  }

  function _getNFTStakingManagerStorage()
    private
    pure
    returns (NFTStakingManagerStorage storage $)
  {
    // solhint-disable-next-line no-inline-assembly
    assembly {
      $.slot := NFT_STAKING_MANAGER_STORAGE_LOCATION
    }
  }

  /**
   * @notice Locks NFTs by transferring them to this contract
   * @param nftIds Array of NFT IDs to lock
   * @return lockedCount Number of NFTs successfully locked
   */
  function _lockNFTs(uint256[] memory nftIds) internal returns (uint256 lockedCount) {
    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();
    for (uint256 i = 0; i < nftIds.length; i++) {
      uint256 nftId = nftIds[i];
      require($.nftToValidationId[nftId] == bytes32(0), "NFTStakingManager: NFT already staked");

      // Transfer NFT to this contract
      IERC721($._nftContract).safeTransferFrom(msg.sender, address(this), nftId);

      // Update tracking
      $.nftToValidationId[nftId] = bytes32(0); // Temporarily set to zero until validationID is generated
      $.nftCounts[msg.sender]++; // Increment the NFT count for the staker
      lockedCount++;
    }

    return lockedCount;
  }

  /**
   * @notice Unlocks NFTs by transferring them back to the specified recipient
   * @param recipient Address to receive the unlocked NFTs
   * @param nftIds Array of NFT IDs to unlock
   * @return unlockedCount Number of NFTs successfully unlocked
   */
  function _unlockNFTs(
    address recipient,
    uint256[] memory nftIds
  ) internal returns (uint256 unlockedCount) {
    require(recipient != address(0), "NFTStakingManager: Invalid recipient");
    require(nftIds.length > 0, "NFTStakingManager: No NFTs to unlock");

    NFTStakingManagerStorage storage $ = _getNFTStakingManagerStorage();

    for (uint256 i = 0; i < nftIds.length; i++) {
      uint256 nftId = nftIds[i];

      // Verify this contract owns the NFT
      require(
        $._nftContract.ownerOf(nftId) == address(this),
        "NFTStakingManager: Contract does not own NFT"
      );

      $._nftContract.safeTransferFrom(address(this), recipient, nftId);
      $.nftCounts[recipient]--; // Decrement the NFT count for the recipient
      unlockedCount++;
    }

    emit NFTsUnlocked(recipient, nftIds);
    return unlockedCount;
  }

}
