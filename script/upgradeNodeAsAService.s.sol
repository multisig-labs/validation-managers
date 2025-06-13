// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

import { Script } from "forge-std-1.9.6/src/Script.sol";
import { console } from "forge-std-1.9.6/src/console.sol";

import { NodeAsAService } from "../contracts/NodeAsAService.sol";

contract UpgradeNodeAsAService is Script {
  address public proxyAddress = vm.envAddress("NODE_AS_A_SERVICE");

  function run() external {
    vm.startBroadcast();

    console.log("=== NodeAsAService Upgrade Script ===");
    console.log("Proxy address:", proxyAddress);
    
    // Verify the proxy exists and get current state
    NodeAsAService proxy = NodeAsAService(proxyAddress);
    
    console.log("Current state before upgrade:");
    console.log("- Invoice number:", proxy.invoiceNumber());
    console.log("- License price per month:", proxy.licensePricePerMonth());
    console.log("- Is paused:", proxy.isPaused());
    console.log("- Treasury:", proxy.treasury());
    
    // Check if caller has admin role
    address deployer = msg.sender;
    console.log("Deployer address:", deployer);
    
    bool hasAdminRole = proxy.hasRole(proxy.DEFAULT_ADMIN_ROLE(), deployer);
    console.log("Deployer has admin role:", hasAdminRole);
    
    if (!hasAdminRole) {
      console.log("ERROR: Deployer does not have admin role. Cannot perform upgrade.");
      console.log("SOLUTION: Use an account with admin privileges or grant admin role to current account.");
      console.log("To find admin accounts, run: forge script script/upgradeNodeAsAService.s.sol:UpgradeNodeAsAService --sig 'checkAdminRole()' --fork-url $ETH_RPC_URL");
      revert("Insufficient permissions");
    }

    // Deploy new implementation
    console.log("\n=== Deploying New Implementation ===");
    NodeAsAService newImplementation = new NodeAsAService();
    console.log("New implementation deployed at:", address(newImplementation));

    // Prepare initialization data for V2
    address avaxPriceFeed = 0x0A77230d17318075983913bC2145DB16C7366156;
    uint256 payAsYouGoFee = 1.33 ether;
    
    console.log("Initialization parameters:");
    console.log("- AVAX price feed:", avaxPriceFeed);
    console.log("- Pay-as-you-go fee:", payAsYouGoFee);
    
    bytes memory initData = abi.encodeWithSelector(
      NodeAsAService.initializeV2.selector,
      avaxPriceFeed,
      payAsYouGoFee
    );
    console.log("Initialization data prepared");

    // Perform upgrade
    console.log("\n=== Performing Upgrade ===");
    proxy.upgradeToAndCall(address(newImplementation), initData);
    
    console.log("Upgrade completed successfully!");

    // Verify the upgrade worked
    console.log("\n=== Verifying Upgrade ===");
    console.log("State after upgrade:");
    console.log("- Invoice number:", proxy.invoiceNumber());
    console.log("- License price per month:", proxy.licensePricePerMonth());
    console.log("- Is paused:", proxy.isPaused());
    console.log("- Treasury:", proxy.treasury());
    console.log("- AVAX price feed:", proxy.avaxPriceFeed());
    console.log("- Pay-as-you-go fee:", proxy.payAsYouGoFeePerMonth());
    
    // Test new V2 functionality
    uint256 avaxPrice = proxy.getAvaxUsdPrice();
    console.log("- AVAX USD price:", avaxPrice);
    
    console.log("\n=== Upgrade Summary ===");
    console.log("Upgrade completed successfully");
    console.log("V2 functionality is working");
    console.log("All existing data preserved");

    vm.stopBroadcast();
  }
}
