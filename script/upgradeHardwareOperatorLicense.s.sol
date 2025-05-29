// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

import { UUPSUpgradeable } from
  "@openzeppelin-contracts-upgradeable-5.3.0/proxy/utils/UUPSUpgradeable.sol";
import { Script } from "forge-std-1.9.6/src/Script.sol";
import { console } from "forge-std-1.9.6/src/console.sol";

import { HardwareOperatorLicense } from "../contracts/tokens/HardwareOperatorLicense.sol";

contract UpgradeHardwareOperatorLicense is Script {
  address public proxyAddress = vm.envAddress("HWOP_LICENSE");

  function run() external {
    vm.startBroadcast();

    address implementation = address(new HardwareOperatorLicense());
    console.log("New implementation deployed at ", implementation);
    console.log("proxyaddress", proxyAddress);

    bytes memory data = "";
    UUPSUpgradeable(proxyAddress).upgradeToAndCall(implementation, data);

    vm.stopBroadcast();
  }
}
