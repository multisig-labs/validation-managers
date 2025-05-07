
# Setup and Deployment


## Environment variables
All scripts rely on these two environment variables 

`ETH_RPC_URL` . RPC url of the subnet

`PRIVATE_KEY` of deployer

## To upgrade AvaCloud ValidatorManager contracts
Firstly, update the `ValidatorManager` that was deployed by default on Avacloud. 

You'll need the validationIDs of the current validators. You can find them with the following curl command. 

```
curl --silent 'https://glacier-api.avax.network/v1/networks/fuji/l1Validators?pageSize=10&includeInactiveL1Validators=true&subnetId=xpt4i8H4UQ4xg1B6aW6WaTT7UrSthvs8dK1uu7LTZma8f6qLW' | jq
```

Copy all `validationIdHex` values. Set them as an environment variable `VALIDTION_IDS`, comma separated.

`VALIDTION_IDS=<id1>,<id2>`


If different than stock, edit the `proxyAddress` and `proxyAdminAddress` in `upgradeStockVM.s.sol` to match the address of the existing `ValidatorManager` and the admin address used to deploy it.

Then upgrade by running 

```
forge script upgradeStockVM.s.sol --broadcast
```


## Deploy NodeLicense

NodeLicense is the NFT that contributes to the stake weight of a validator through delegation.

Refer to the desription of the settings in `NodeLicenese.sol` and set them in the deployment script `deployNodeLicense.s.sol`

```
NodeLicenseSettings memory settings = NodeLicenseSettings({
  admin: msg.sender,
  minter: msg.sender,
  nftStakingManager: address(0x00),
  name: "Node License",
  symbol: "NL",
  baseTokenURI: "https://example.com/node-license",
  unlockTime: uint32(block.timestamp)
});
```

deploy with 

```
forge script deployNodeLicense.s.sol --broadcast
```


## HardwareOperatorLicense

This license is staked to create validators, for node license delegation

Again, check out `HardwareOperatorLicense.sol` for setting information and set them in the deploy script

```
bytes memory initData = abi.encodeWithSelector(
  HardwareOperatorLicense.initialize.selector,
  defaultAdmin,
  minter,
  name,
  symbol,
  baseTokenURI
);
```

```
forge script deployHardwareOperatorLicense.s.sol --broadcast
```

## NFTStakingManager

Now we're ready to deploy the NFTStakingManager. 

Set the newly deployed NodeLicense and HardwareOperatorLicense addresses as environment variables. 

`NODE_LICENSE` and `HWOP_LICENSE`

Next configure settings in `deployNFTStakingManager.s.sol`

```
struct NFTStakingManagerSettings {
  bool bypassUptimeCheck; // flag to bypass uptime check
  uint16 uptimePercentage; // 100 = 100%, per epoch validator uptime requirement for rewards
  uint16 maxLicensesPerValidator; // max node licenses that can be staked to a validator
  uint32 initialEpochTimestamp; // timestamp when rewards epochs will start
  uint32 epochDuration; // duration of epoch in seconds
  uint32 gracePeriod; // period after end of an epoch for uptime proofs, in seconds
  uint64 licenseWeight; // weight that each NodeLicense contributes to the overall validator weight
  uint64 hardwareLicenseWeight; // weight of the hardware license by itself
  address admin; // default admin address
  address validatorManager; // address of validator manager
  address license; // address of node license
  address hardwareLicense; // address of hardware license
  uint256 epochRewards; // amount of rewards per epoch
}
```

and run 

```
forge script deployNFTStakingManager.s.sol --broadcast
```

## After deployment
Now you can create a validator!

1. Mint a HardwareOperatorLicense to a user. 
2. Call `NFTStakingManager::initiateValidatorRegistration` with all of the hardware node information.
3. With the warp message index call `NFTStakingManager::completeValidatorRegistration`. We have a backend system that will watch for warp messages and automatically call these `complete` methods that we will setup for you.
4. Now NodeLicenses can delegate with `NFTStakingManager::initiateDelegatorRegistration`. 
5. Complete by calling `NFTStakingManager::completeDelegatorRegistration`. 



