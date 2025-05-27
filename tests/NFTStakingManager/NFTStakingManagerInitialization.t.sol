// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

import { NFTStakingManager, NFTStakingManagerSettings } from "../../contracts/NFTStakingManager.sol";
import { NFTStakingManagerBase } from "../utils/NFTStakingManagerBase.sol";

contract NFTStakingManagerInitializationTest is NFTStakingManagerBase {
  //
  // INITIALIZATION
  //
  function test_initialization_defaultSettings() public view {
    NFTStakingManagerSettings memory expectedSettings = _defaultNFTStakingManagerSettings(
      address(validatorManager), address(nft), address(hardwareNft)
    );

    NFTStakingManagerSettings memory actualSettings = nftStakingManager.getSettings();

    assertEq(
      actualSettings.validatorManager,
      expectedSettings.validatorManager,
      "validatorManager mismatch"
    );
    assertEq(actualSettings.nodeLicense, expectedSettings.nodeLicense, "license mismatch");
    assertEq(
      actualSettings.hardwareLicense, expectedSettings.hardwareLicense, "hardwareLicense mismatch"
    );
    assertEq(
      actualSettings.initialEpochTimestamp,
      expectedSettings.initialEpochTimestamp,
      "initialEpochTimestamp mismatch"
    );
    assertEq(actualSettings.epochDuration, expectedSettings.epochDuration, "epochDuration mismatch");
    assertEq(
      actualSettings.nodeLicenseWeight,
      expectedSettings.nodeLicenseWeight,
      "nodeLicenseWeight mismatch"
    );
    assertEq(
      actualSettings.hardwareLicenseWeight,
      expectedSettings.hardwareLicenseWeight,
      "hardwareLicenseWeight mismatch"
    );
    assertEq(actualSettings.epochRewards, expectedSettings.epochRewards, "epochRewards mismatch");
    assertEq(
      actualSettings.maxLicensesPerValidator,
      expectedSettings.maxLicensesPerValidator,
      "maxLicensesPerValidator mismatch"
    );
    assertEq(actualSettings.gracePeriod, expectedSettings.gracePeriod, "gracePeriod mismatch");
    assertEq(
      actualSettings.uptimePercentageBips,
      expectedSettings.uptimePercentageBips,
      "uptimePercentageBips mismatch"
    );
    assertEq(
      actualSettings.bypassUptimeCheck,
      expectedSettings.bypassUptimeCheck,
      "bypassUptimeCheck mismatch"
    );
    assertEq(
      actualSettings.minDelegationEpochs,
      expectedSettings.minDelegationEpochs,
      "minDelegationEpochs mismatch"
    );
  }

  function test_getEpochByTimestamp() public view {
    uint32 currentEpoch = nftStakingManager.getEpochByTimestamp(block.timestamp);
    assertGt(currentEpoch, 0, "Epoch should be greater than 0");
  }

  function test_getEpochEndTime() public view {
    uint32 currentEpoch = nftStakingManager.getEpochByTimestamp(block.timestamp);
    uint32 endTime = nftStakingManager.getEpochEndTime(currentEpoch);
    assertGt(endTime, block.timestamp, "End time should be in the future");
  }
}
