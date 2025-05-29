# Validation Manager Contracts

# NodeLicense
An ERC721 token that represents a license to delegate stake to a validator. These tokens can be staked in the NFTStakingManager to add weight to a validator's total stake. The tokens are transferable and can be approved, but may be locked during staking periods or until a specified unlock time. Each token has a fixed weight that contributes to the validator's total stake weight.

```solidity
// Minting
function mint(address to) public returns (uint256)
function batchMint(address[] calldata recipients, uint256[] calldata amounts) public

// Transfer
function batchTransferFrom(address from, address to, uint256[] memory tokenIds) public

// Admin Controls
function setBaseURI(string memory baseTokenURI) public
function setNFTStakingManager(address nftStakingManager) public
function setUnlockTime(uint32 newUnlockTime) public

// View Functions
function getNFTStakingManager() external view returns (address)
function getUnlockTime() external view returns (uint32)
```

# HardwareOperatorLicense
An ERC721 Soulbound token that represents a hardware operator license. These tokens are permanently bound to their owner (non-transferable) and are used to stake in the NFTStakingManager to create validator nodes. The soulbound nature ensures that the hardware operator's identity and reputation remain tied to their license. Each token has a fixed weight that contributes to the validator's total stake weight.

```solidity
// Minting
function mint(address to) public returns (uint256)

// Admin Controls
function setBaseURI(string memory baseTokenURI) public

// View Functions
function _baseURI() internal view returns (string memory)
```


# NFTStakingManager

Manage validation and node license delegation.

## State management

###  Validation state
```
Bytes32Set validationIDs;
mapping(bytes32 validationID => ValidationInfo);
mapping(uint256 hardwareTokenID => bytes32 validationID) hardwareTokenLockedby; 

struct ValidationInfo {
  uint32 startEpoch; 
  uint32 endEpoch; 
  uint32 licenseCount; 
  uint32 lastUptimeSeconds; 
  uint32 lastSubmissionTime; 
  uint32 delegationFeeBips; 
  address owner; 
  uint256 hardwareTokenID; 
  bytes registrationMessage; 
  EnumerableSet.Bytes32Set delegationIDs;
  mapping(uint32 epochNumber => uint256 rewards) claimableRewardsPerEpoch; 
}

```

### Delegation state
```
mapping(bytes32 delegationID => DelegationInfo) delegations;
mapping(uint256 nodeLicenseTokenID => bytes32 delegationID) tokenLockedBy;
mapping(address hardwareOperator => Map(address,uint)) prepaidCredits;

struct DelegationInfo {
  uint32 startEpoch;
  uint32 endEpoch;
  address owner;
  bytes32 validationID;
  uint256[] tokenIDs;
  mapping(uint32 epochNumber => uint256 rewards) claimableRewardsPerEpoch; 
  mapping(uint32 epochNumber => bool passedUptime) uptimeCheck;
  EnumerableSet.UintSet claimableEpochNumbers;
}
```

### Epoch state
```
mapping(uint32 epochNumber => EpochInfo) epochs;
mapping(uint32 epochNumber => mapping(uint256 tokenID => bool isRewardsMinted)) isRewardsMinted;

struct EpochInfo {
  uint256 totalStakedLicenses;
}

```

### State changing functions

#### Validator Functions
- `initiateValidatorRegistration`
- `completeValidatorRegistration`
- `initiateValidatorRemoval`
- `completeValidatorRemoval`

#### Delegator Functions
- `initiateDelegatorRegistration`
- `initiateDelegatorRegistrationOnBehalfOf`
- `completeDelegatorRegistration`
- `initiateDelegatorRemoval`
- `completeDelegatorRemoval`

#### Rewards and Proof Functions
- `addPrepaidCredits`
- `submitUptimeProof`
- `mintRewards`
- `claimRewards`

### Validator add and remove

|var|initReg|completeReg|initRemoval|completeRemoval|
|---|---|---|---|---|
|`set::validationIDs`|add|-|-|delete|
|`v::startEpoch`|-|record|-|-|
|`v::endEpoch`|-|-|record|-|
|`v::licenseCount`|-|-|-|-|
|`v::lastUptimeSeconds`|-|-|-|-|
|`v::lastSubmissionTime`|-|-|-|-|
|`v::delegationFeeBips`|set|-|-|-|
|`v::owner`|set|-|-|-|
|`v::hardwareTokenID`|set|-|-|-|
|`v::registrationMessage`|set|-|-|-|
|`v::delegationIDs`|-|-|-|remove|
|`v::map::claimableRewardsPerEpoch`|-|-|-|-|

### Delegator add and remove

|var|initDelReg|completeDelReg|initDelRemoval|completeDelRemoval|
|---|---|---|---|---|
|`map::tokenLockedBy`|add|-|-|delete|
|`d::startEpoch`|-|record|-|-|
|`d::endEpoch`|-|-|record - 1|-|
|`d::owner`|set|-|-|-|
|`d::validationID`|set|-|-|-|
|`d::tokenIDs`|set|-|-|-|
|`d::map::claimableRewardsPerEpoch`|-|-|-|-|
|`d::map::uptimeCheck`|-|-|-|-|
|`d::map::claimableEpochNumbers`|-|-|-|-|
|`v::licenseCount`|inc|-|dec|-|
|`v::delegationIDs`|add|-|-|-|

### Rewards and Proof Functions

|var|addPrepaidCredits|submitUptimeProof|mintRewards|claimRewards|
|---|---|---|---|---|
|`map::prepaidCredits`|add|-|-|-|
|`v::lastUptimeSeconds`|-|update|-|-|
|`v::lastSubmissionTime`|-|update|-|-|
|`map::epochs`|-|update totalStakedLicenses|-|-|
|`d::map::uptimeCheck`|-|set to true|-|-|
|`d::map::claimableRewardsPerEpoch`|-|-|set|-|
|`v::map::claimableRewardsPerEpoch`|-|-|add delegation fee|-|
|`d::map::claimableEpochNumbers`|-|-|add|-|
|`map::isRewardsMinted`|-|-|set to true|-|
|`d::map::claimableRewardsPerEpoch`|-|-|-|set to 0|
|`d::map::claimableEpochNumbers`|-|-|-|remove|
