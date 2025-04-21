// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

import { ERC1967Proxy } from "@openzeppelin-contracts-5.3.0/proxy/ERC1967/ERC1967Proxy.sol";
import { Script } from "forge-std-1.9.6/src/Script.sol";
import { console } from "forge-std-1.9.6/src/console.sol";

import { NodeLicense, NodeLicenseSettings } from "../contracts/tokens/NodeLicense.sol";

contract DeployNodeLicense is Script {
  address public nftStakingManager = 0x0Feedc0de0000000000000000000000000000000;

  function run() external {
    vm.startBroadcast();

    NodeLicense impl = new NodeLicense();
    console.log("NodeLicense implementation deployed at ", address(impl));

    NodeLicenseSettings memory settings = NodeLicenseSettings({
      admin: msg.sender,
      minter: msg.sender,
      nftStakingManager: address(0x00),
      name: "Node License",
      symbol: "NL",
      baseTokenURI: "https://example.com/node-license",
      unlockTime: uint32(block.timestamp)
    });
    bytes memory initData = abi.encodeWithSelector(NodeLicense.initialize.selector, settings);

    ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
    console.log("NodeLicense UUPS proxy deployed at ", address(proxy));

    vm.stopBroadcast();
  }
}
