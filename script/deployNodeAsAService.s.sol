// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

import { ERC1967Proxy } from "@openzeppelin-contracts-5.3.0/proxy/ERC1967/ERC1967Proxy.sol";
import { Script } from "forge-std-1.9.6/src/Script.sol";
import { console } from "forge-std-1.9.6/src/console.sol";

import { NodeAsAService } from "../contracts/NodeAsAService.sol";

contract DeployNodeAsAService is Script {
  address public usdc = 0x5425890298aed601595a70AB815c96711a31Bc65; // Fuji USDC address
  address public admin = vm.envAddress("ETH_FROM");
  address public protocolManager = vm.envAddress("ETH_FROM");
  address public treasury = vm.envAddress("ETH_FROM");
  uint256 public initialPricePerMonth = 0.02 * 1e6; // 2 cents USDC per month

  function run() external {
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    vm.startBroadcast(deployerPrivateKey);

    NodeAsAService impl = new NodeAsAService();
    console.log("NodeAsAService implementation deployed at:", address(impl));

    bytes memory initData = abi.encodeWithSelector(
      NodeAsAService.initialize.selector, usdc, admin, initialPricePerMonth, treasury
    );

    ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
    console.log("NodeAsAService UUPS proxy deployed at:", address(proxy));

    console.log("\nVerification commands:");
    console.log(
      "forge verify-contract",
      address(impl),
      "contracts/NodeAsAService.sol:NodeAsAService --verifier-url 'https://api.routescan.io/v2/network/testnet/evm/43113/etherscan' --etherscan-api-key 'verifyContract' --num-of-optimizations 200 --compiler-version v0.8.25"
    );
    console.log(
      "forge verify-contract",
      address(proxy),
      "dependencies/@openzeppelin-contracts-5.3.0/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy --verifier-url 'https://api.routescan.io/v2/network/testnet/evm/43113/etherscan' --etherscan-api-key 'verifyContract' --num-of-optimizations 200 --compiler-version v0.8.25 --constructor-args $(cast abi-encode 'constructor(address,bytes)' address(impl) initData)"
    );

    vm.stopBroadcast();
  }
}
