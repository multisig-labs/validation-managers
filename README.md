# Validation Manager Contracts

## NodeLicense
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

## HardwareOperatorLicense
An ERC721 Soulbound token that represents a hardware operator license. These tokens are permanently bound to their owner (non-transferable) and are used to stake in the NFTStakingManager to create validator nodes. The soulbound nature ensures that the hardware operator's identity and reputation remain tied to their license. Each token has a fixed weight that contributes to the validator's total stake weight.

```solidity
// Minting
function mint(address to) public returns (uint256)

// Admin Controls
function setBaseURI(string memory baseTokenURI) public

// View Functions
function _baseURI() internal view returns (string memory)
```
