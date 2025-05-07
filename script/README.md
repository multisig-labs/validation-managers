# Setup and Deployment


## Environment variables
All scripts rely on these two environment variables 

|env var| description |
|---|---|
| `ETH_RPC_URL` | RPC url of the subnet|
| `PRIVATE_KEY` | private key of deployer|

## 1. Upgrade AvaCloud ValidatorManager contracts
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


## 2. Deploy NodeLicense

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


## 3. HardwareOperatorLicense

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

## 4. NFTStakingManager

Now we're ready to deploy the NFTStakingManager. 

Set the newly deployed NodeLicense and HardwareOperatorLicense addresses as environment variables. 

`NODE_LICENSE` and `HWOP_LICENSE`

Next configure settings in `deployNFTStakingManager.s.sol`

| Setting | Type | Description |
|---|---|---|
| `bypassUptimeCheck` | bool | Flag to bypass uptime check during testing |
| `uptimePercentage` | uint16 | Required uptime percentage per epoch (100 = 100%) |
| `maxLicensesPerValidator` | uint16 | Maximum number of node licenses that can be staked to a validator |
| `initialEpochTimestamp` | uint32 | Timestamp when rewards epochs will start |
| `epochDuration` | uint32 | Duration of each epoch in seconds |
| `gracePeriod` | uint32 | Period after end of an epoch for uptime proofs, in seconds |
| `licenseWeight` | uint64 | Weight that each NodeLicense contributes to validator weight |
| `hardwareLicenseWeight` | uint64 | Weight of the hardware license by itself |
| `admin` | address | Default admin address |
| `validatorManager` | address | Address of validator manager |
| `license` | address | Address of node license contract |
| `hardwareLicense` | address | Address of hardware license contract |
| `epochRewards` | uint256 | Amount of rewards per epoch |

and run 

```
forge script deployNFTStakingManager.s.sol --broadcast
```

## After deployment
Now you can create a validator!

1. Mint a `HardwareOperatorLicense` to a user. 
2. Call `NFTStakingManager::initiateValidatorRegistration` with all of the hardware node information.
3. With the warp message index call `NFTStakingManager::completeValidatorRegistration`. We have a backend system that will watch for warp messages and automatically call these `complete` methods that we will setup for you.
3. Mint a `NodeLicense` to a user
4. Now NodeLicenses can delegate with `NFTStakingManager::initiateDelegatorRegistration`. 
5. Complete by calling `NFTStakingManager::completeDelegatorRegistration`. 



