// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

import { ERC1967Proxy } from "@openzeppelin-contracts-5.3.0/proxy/ERC1967/ERC1967Proxy.sol";
import { Script } from "forge-std-1.9.6/src/Script.sol";
import { console } from "forge-std-1.9.6/src/console.sol";

import { NFTStakingManager, NFTStakingManagerSettings } from "../contracts/NFTStakingManager.sol";
import { ValidatorManager } from
  "icm-contracts-d426c55/contracts/validator-manager/ValidatorManager.sol";

contract DeployNFTStakingManager is Script {
  address public proxyAddress = 0x0Feedc0de0000000000000000000000000000000;
  address public licenseAddress = vm.envAddress("NODE_LICENSE");
  address public hardwareLicenseAddress = vm.envAddress("HWOP_LICENSE");

  function run() external {
    vm.startBroadcast();

    NFTStakingManager nftsmImpl = new NFTStakingManager();
    console.log("NFTStakingManager implementation deployed at ", address(nftsmImpl));

    // --- Deploy NFTStakingManager UUPS Proxy ---

    // TODO: Configure settings for NFTStakingManager initialization
    NFTStakingManagerSettings memory settings = NFTStakingManagerSettings({
      admin: msg.sender, // Or specify another admin address
      validatorManager: proxyAddress, // Address of the upgraded ValidatorManager proxy
      license: licenseAddress,
      hardwareLicense: hardwareLicenseAddress,
      initialEpochTimestamp: uint32(block.timestamp), // Or specify a fixed timestamp
      epochDuration: 1 days, // Example: 1 day
      licenseWeight: 10, // Example value
      hardwareLicenseWeight: 1, // Example value
      epochRewards: 1000 ether, // Example value
      maxLicensesPerValidator: 50, // Example value
      gracePeriod: 1 hours, // Example value
      uptimePercentageBips: 8000, // Example value (95%)
      bypassUptimeCheck: true,
      minDelegationEpochs: 0
    });

    bytes memory nftsmInitData =
      abi.encodeWithSelector(NFTStakingManager.initialize.selector, settings);

    ERC1967Proxy nftsmProxy = new ERC1967Proxy(address(nftsmImpl), nftsmInitData);
    console.log("NFTStakingManager UUPS proxy deployed at ", address(nftsmProxy));

    ValidatorManager vmgr = ValidatorManager(proxyAddress);
    vmgr.transferOwnership(address(nftsmProxy));
    console.log("ValidatorManager transferred ownership to NFTStakingManager UUPS proxy");

    vm.stopBroadcast();
  }
}
