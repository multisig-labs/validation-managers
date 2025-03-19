// SPDX-License-Identifier: Ecosystem

pragma solidity 0.8.25;

interface INFTLicenseModule {
  function validateValidator(address user) external view returns (bool);
  function validateDelegator(address user) external view returns (bool);
  function validateLicense(address nftAddress, uint256 nftId) external view returns (bool);
  function licenseToWeight(address nftAddress, uint256 nftId) external view returns (uint64);
  function calculateReward(
    address nftAddress,
    uint256 nftId,
    uint64 validatorStartTime,
    uint64 stakingStartTime,
    uint64 stakingEndTime,
    uint64 uptimeSeconds
  ) external view returns (uint256);
}
