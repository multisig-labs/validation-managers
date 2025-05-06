// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {
  DelegationInfo,
  DelegatorStatus,
  NFTStakingManager,
  NFTStakingManagerSettings,
  ValidationInfo
} from "./NFTStakingManager.sol";

struct ValidationInfoView {
  uint32 startEpoch;
  uint32 endEpoch;
  uint32 licenseCount;
  uint32 lastUptimeSeconds;
  uint32 lastSubmissionTime;
  uint32 delegationFeeBips;
  address owner;
  uint256 hardwareTokenID;
  bytes registrationMessage;
}

struct DelegationInfoView {
  DelegatorStatus status;
  uint32 startEpoch;
  uint32 endEpoch;
  uint64 startingNonce;
  uint64 endingNonce;
  address owner;
  bytes32 validationID;
  uint256[] tokenIDs;
}

library NFTStakingManagerViews {
  function getValidationInfoView(
    NFTStakingManager.NFTStakingManagerStorage storage $,
    bytes32 validationID
  ) public view returns (ValidationInfoView memory) {
    ValidationInfo storage validation = $.validations[validationID];
    return ValidationInfoView({
      owner: validation.owner,
      hardwareTokenID: validation.hardwareTokenID,
      startEpoch: validation.startEpoch,
      endEpoch: validation.endEpoch,
      licenseCount: validation.licenseCount,
      registrationMessage: validation.registrationMessage,
      lastUptimeSeconds: validation.lastUptimeSeconds,
      lastSubmissionTime: validation.lastSubmissionTime,
      delegationFeeBips: validation.delegationFeeBips
    });
  }

  function getDelegationInfoView(
    NFTStakingManager.NFTStakingManagerStorage storage $,
    bytes32 delegationID
  ) public view returns (DelegationInfoView memory) {
    DelegationInfo storage delegation = $.delegations[delegationID];
    return DelegationInfoView({
      status: delegation.status,
      owner: delegation.owner,
      validationID: delegation.validationID,
      startEpoch: delegation.startEpoch,
      endEpoch: delegation.endEpoch,
      startingNonce: delegation.startingNonce,
      endingNonce: delegation.endingNonce,
      tokenIDs: delegation.tokenIDs
    });
  }

  function getSettings(NFTStakingManager.NFTStakingManagerStorage storage $)
    public
    view
    returns (NFTStakingManagerSettings memory)
  {
    // Explicitly create a memory struct and copy fields from storage
    NFTStakingManagerSettings memory settings = NFTStakingManagerSettings({
      bypassUptimeCheck: $.bypassUptimeCheck,
      uptimePercentage: $.uptimePercentage,
      maxLicensesPerValidator: $.maxLicensesPerValidator,
      initialEpochTimestamp: $.initialEpochTimestamp,
      epochDuration: $.epochDuration,
      gracePeriod: $.gracePeriod,
      licenseWeight: $.licenseWeight,
      hardwareLicenseWeight: $.hardwareLicenseWeight,
      validatorManager: address($.manager),
      license: address($.licenseContract),
      hardwareLicense: address($.hardwareLicenseContract),
      epochRewards: $.epochRewards,
      admin: address(0) // How to get defaultAdmin()?
     });

    return settings;
  }
}
