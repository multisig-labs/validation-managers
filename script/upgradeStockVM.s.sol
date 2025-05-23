// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

import { ProxyAdmin } from "@openzeppelin-contracts-5.3.0/proxy/transparent/ProxyAdmin.sol";
import { ITransparentUpgradeableProxy } from
  "@openzeppelin-contracts-5.3.0/proxy/transparent/TransparentUpgradeableProxy.sol";
import { Script } from "forge-std-1.9.6/src/Script.sol";
import { console } from "forge-std-1.9.6/src/console.sol";

import { ICMInitializable } from "icm-contracts-2.0.0/contracts/utilities/ICMInitializable.sol";
import { ValidatorManager } from
  "icm-contracts-2.0.0/contracts/validator-manager/ValidatorManager.sol";

contract UpgradeValidatorManager is Script {
  address public proxyAddress = 0x0Feedc0de0000000000000000000000000000000;
  address public proxyAdminAddress = 0xC0fFEE1234567890aBCdeF1234567890abcDef34;

  function run() external {
    bytes32[] memory validationIDs = vm.envBytes32("VALIDATION_IDS", ",");

    vm.startBroadcast();

    address implementation = address(new ValidatorManager(ICMInitializable.Disallowed));
    console.log("Implementation deployed at ", implementation);

    // HACK If data = bytes("") then the upgrade will fail for unknown reasons, so call a harmless view function.
    bytes memory data = abi.encodeCall(ValidatorManager.l1TotalWeight, ());
    ProxyAdmin(proxyAdminAddress).upgradeAndCall(
      ITransparentUpgradeableProxy(proxyAddress), implementation, data
    );
    console.log("Proxy upgraded at ", proxyAddress);

    ValidatorManager vmgr = ValidatorManager(proxyAddress);
    for (uint256 i = 0; i < validationIDs.length; i++) {
      console.log("Migrating validationID");
      vmgr.migrateFromV1(validationIDs[i], 0);
    }
    vm.stopBroadcast();
  }
}
