// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {INFTLicenseModule} from "../interfaces/INFTLicenseModule.sol";
import "@openzeppelin-contracts-upgradeable-5.2.0/access/OwnableUpgradeable.sol";
import "@openzeppelin-contracts-upgradeable-5.2.0/proxy/utils/Initializable.sol";
import "@openzeppelin-contracts-upgradeable-5.2.0/proxy/utils/UUPSUpgradeable.sol";
import {IRewardCalculator} from "icm-contracts/contracts/validator-manager/interfaces/IRewardCalculator.sol";

interface ICertificates {
  function tokenByCollection(address account, bytes32 collection) external view returns (uint256);
}

/// @notice Contract for checking if a user is allowed to be a validator or delegator based on their NFT holdings.
/// Each L1 would deploy their own copy of this and configure it with the appropriate NFT address and weights.
/// The ValidatorManager contract would call out to this module at the appropriate times.
/// @dev This contract is upgradable.

contract NFTLicenseModule is INFTLicenseModule, Initializable, UUPSUpgradeable, OwnableUpgradeable {
  /// @notice Address of the Certificate NFT contract that holds KYC certs, etc.
  address public _certificateNFTAddress;

  /// @notice Mapping of _keyFrom(nftAddress, nftId) to weight.
  ///         nftId=0 signifies the default weight for the NFT address.
  ///         If a different weight is specified for the nftId then that weight is used instead of the default.
  mapping(bytes32 nftAddrAndId => uint64 weight) private _nftWeights;

  /// @notice Event emitted when the certificate NFT address is updated.
  event CertificateNFTAddressUpdated(address indexed newAddress);

  /// @notice Event emitted when the default weight for an NFT address is set.
  event AllowedNFTSet(address indexed nftAddress, uint64 defaultWeight);

  /// @notice Event emitted when the weight for a specific NFT ID is set.
  event NFTWeightSet(address indexed nftAddress, uint256 indexed nftId, uint64 weight);

  function initialize(address owner) public initializer {
    __Ownable_init(owner);
    __UUPSUpgradeable_init();
  }

  /// @notice Check if user holds whatever required NFT Certificates (KYC, etc)
  function validateValidator(address user) external view returns (bool) {
    ICertificates certificates = ICertificates(_certificateNFTAddress);
    uint256 tokenId = certificates.tokenByCollection(user, keccak256("KYC"));
    return tokenId > 0;
  }

  /// @notice Check if user holds whatever required NFT Certificates (KYC, etc)
  function validateDelegator(address user) external view returns (bool) {
    // In this example anyone can delegate.
    return true;
  }

  /// @notice Check if this NFT is allowed to be used as a license.
  // TODO maybe combine with licenseToWeight and just check for > 0 to be valid?
  function validateLicense(address nftAddress, uint256 nftId) external view returns (bool) {
    return licenseToWeight(nftAddress, nftId) > 0;
  }

  /// @notice Calculate the reward for a validator based on their NFT License and uptime.
  function calculateReward(
    address nftAddress,
    uint256 nftId,
    uint64 validatorStartTime,
    uint64 stakingStartTime,
    uint64 stakingEndTime,
    uint64 uptimeSeconds
  ) external view returns (uint256) {
    return 1 ether; // fake it for now
  }

  /// @notice Returns the weight associated with an NFT, first checking if a specific weight is set, otherwise default.
  function licenseToWeight(address nftAddress, uint256 nftId) public view returns (uint64) {
    // Returns static values, but could be dynamic if we wanted to determine the weight of an NFT by some algorithm.
    uint64 defaultWeight = _nftWeights[_keyFrom(nftAddress, uint256(0))];
    uint64 idWeight = _nftWeights[_keyFrom(nftAddress, nftId)];
    return (idWeight > 0) ? idWeight : defaultWeight;
  }

  /// @dev Constructs a bytes32 key from nftAddress and nftId.
  function _keyFrom(address nftAddress, uint256 nftId) internal pure returns (bytes32) {
    return keccak256(abi.encode(nftAddress, nftId));
  }

  // UPDATE FUNCTIONS

  /// @notice Set the address of the Certificate NFT contract
  /// @param nftAddress The NFT address.
  function setCertificateNFTAddress(address nftAddress) external onlyOwner {
    _certificateNFTAddress = nftAddress;
    emit CertificateNFTAddressUpdated(nftAddress);
  }

  /// @notice Set the allowed status (default weight) of an NFT address.
  /// @param nftAddress The NFT address.
  /// @param defaultWeight The default weight for this NFT address.
  function setAllowedNFT(address nftAddress, uint64 defaultWeight) external onlyOwner {
    require(nftAddress != address(0), "Invalid NFT address");
    _nftWeights[_keyFrom(nftAddress, uint256(0))] = defaultWeight;
    emit AllowedNFTSet(nftAddress, defaultWeight);
  }

  /// @notice Set the weight for a specific NFT ID.
  /// @param nftAddress The NFT address.
  /// @param nftId The token ID of the NFT.
  /// @param weight The weight to assign to this specific NFT ID.
  function setWeightForId(address nftAddress, uint256 nftId, uint64 weight) external onlyOwner {
    require(nftAddress != address(0), "Invalid NFT address");
    _nftWeights[_keyFrom(nftAddress, nftId)] = weight;
    emit NFTWeightSet(nftAddress, nftId, weight);
  }

  /// @dev UUPS upgrade authorization - restrict upgrades to the owner
  function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
