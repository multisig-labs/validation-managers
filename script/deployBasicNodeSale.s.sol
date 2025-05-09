// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

import { ERC1967Proxy } from "@openzeppelin-contracts-5.3.0/proxy/ERC1967/ERC1967Proxy.sol";
import { Script } from "forge-std-1.9.6/src/Script.sol";
import { console } from "forge-std-1.9.6/src/console.sol";

import { BasicNodeSale } from "../contracts/node-sale/BasicNodeSale.sol";

contract DeployBasicNodeSale is Script {
    address public usdc = 0x5425890298aed601595a70AB815c96711a31Bc65;
    address public treasury = 0x5e32bAb27EC0B44d490066385f827838C49b61E1; // fuji deployer

    function run() external {
        vm.startBroadcast();

        BasicNodeSale nodeSale = new BasicNodeSale(usdc, treasury);
        console.log("BasicNodeSale deployed at ", address(nodeSale));

        vm.stopBroadcast();
    }
}
