// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

import { ERC1967Proxy } from "@openzeppelin-contracts-5.3.0/proxy/ERC1967/ERC1967Proxy.sol";
import { Script } from "forge-std-1.9.6/src/Script.sol";
import { console } from "forge-std-1.9.6/src/console.sol";

import { HardwareOperatorLicense } from "../contracts/tokens/HardwareOperatorLicense.sol";

contract DeployHardwareOperatorLicense is Script {
  function run() external {
    vm.startBroadcast();

    HardwareOperatorLicense impl = new HardwareOperatorLicense();
    console.log("HardwareOperatorLicense implementation deployed at ", address(impl));

    bytes memory initData = abi.encodeWithSelector(
      HardwareOperatorLicense.initialize.selector,
      msg.sender,
      msg.sender,
      "Hardware Operator License",
      "HOL",
      "https://example.com/hardware-operator-license"
    );

    ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
    console.log("HardwareOperatorLicense UUPS proxy deployed at ", address(proxy));

    vm.stopBroadcast();
  }
}
