// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

import { UUPSUpgradeable } from
  "@openzeppelin-contracts-upgradeable-5.3.0/proxy/utils/UUPSUpgradeable.sol";
import { Script } from "forge-std-1.9.6/src/Script.sol";
import { console } from "forge-std-1.9.6/src/console.sol";

import {
  NFTStakingManagerGasless,
  NFTStakingManagerSettings
} from "../contracts/NFTStakingManagerGasless.sol";

contract UpgradeNFTStakingManagerGasless is Script {
  address public proxyAddress = vm.envAddress("NFT_STAKING_MANAGER");

  function run() external {
    vm.startBroadcast();

    address implementation = address(new NFTStakingManagerGasless());
    console.log("New implementation deployed at ", implementation);

    bytes memory data = "";
    UUPSUpgradeable(proxyAddress).upgradeToAndCall(implementation, data);

    // The storage layout changed so re-write all the settings
    NFTStakingManagerSettings memory settings = NFTStakingManagerSettings({
      validatorManager: 0x0Feedc0de0000000000000000000000000000000,
      nodeLicense: 0x6a87a1caB32C987F945e6dCf0bEEfecA280ceD8a,
      hardwareLicense: 0x02f96245Ce7da17EC2FcD94Af82DE54fba78AE2d,
      initialEpochTimestamp: 1747072211, // Or specify a fixed timestamp
      epochDuration: 1 days, // Example: 1 day
      nodeLicenseWeight: 10, // Example value
      hardwareLicenseWeight: 1, // Example value
      epochRewards: 1000 ether, // Example value
      maxLicensesPerValidator: 50, // Example value
      gracePeriod: 1 hours, // Example value
      uptimePercentageBips: 8000, // Example value (95%)
      bypassUptimeCheck: true,
      minDelegationEpochs: 0
    });

    NFTStakingManagerGasless nfts = NFTStakingManagerGasless(proxyAddress);
    nfts.setSettings(settings);

    vm.stopBroadcast();
  }
}
