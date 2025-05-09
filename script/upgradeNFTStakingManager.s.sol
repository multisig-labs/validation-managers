// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

import { UUPSUpgradeable } from
  "@openzeppelin-contracts-upgradeable-5.3.0/proxy/utils/UUPSUpgradeable.sol";
import { Script } from "forge-std-1.9.6/src/Script.sol";
import { console } from "forge-std-1.9.6/src/console.sol";

import { NFTStakingManager } from "../contracts/NFTStakingManager.sol";

contract UpgradeNFTStakingManager is Script {
  address public proxyAddress = vm.envAddress("NFT_STAKING_MANAGER");

  function run() external {
    vm.startBroadcast();

    address implementation = address(new NFTStakingManager());
    console.log("New implementation deployed at ", implementation);

    bytes memory data = "";
    UUPSUpgradeable(proxyAddress).upgradeToAndCall(implementation, data);

    vm.stopBroadcast();
  }
}
