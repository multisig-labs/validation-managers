# NFTSaleWithWhitelist Contract

## Overview

The `NFTSaleWithWhitelist` contract is an upgradeable smart contract designed to manage the sale of ERC-721 NFTs. It includes features like fixed-price sales, optional whitelisting, sequential token distribution, and administrative controls, all built with security and flexibility in mind using OpenZeppelin's upgradeable contract libraries.

## Features

### 1. Fixed Price NFT Sales

- NFTs are sold at a fixed price (in ETH) set by the admin.
- Users send the exact amount of ETH to purchase an NFT.

### 2. Optional Whitelisting

- Admins can enable whitelisting using a Merkle root.
- Only whitelisted addresses (verified via Merkle proofs) can buy NFTs when whitelisting is active.

### 3. Sequential Token Sales

- NFTs are sold in order, starting from a specified `startingTokenId`.
- The contract assumes NFTs are pre-minted and owned by the contract.

### 4. Purchase Limits

- A maximum number of NFTs per wallet can be set.
- The total supply of NFTs for sale is capped.

### 5. Pausability

- Admins can pause or unpause the sale to control availability.
- The contract starts paused and must be unpaused to begin sales.

### 6. Role-Based Access Control

- Uses OpenZeppelin's `AccessControl` to manage permissions.
- The `ADMIN_ROLE` controls settings, fund withdrawals, and upgrades.

### 7. Upgradeability

- Built with the UUPS (Universal Upgradeable Proxy Standard) pattern.
- Admins can upgrade the contract to new versions as needed.

## Usage

### Deployment

1. **Deploy the Implementation Contract**

   - Deploy the `NFTSaleWithWhitelist` contract (the implementation).
   - Do not interact with it directly.

2. **Deploy the Proxy Contract**
   - Use a UUPS-compatible proxy (e.g., OpenZeppelin's `ERC1967Proxy`).
   - Initialize it with the implementation address and setup data.

#### Example (Hardhat)

```
const NFTSale = await ethers.getContractFactory("NFTSaleWithWhitelist");
const implementation = await NFTSale.deploy();
const Proxy = await ethers.getContractFactory("ERC1967Proxy");
const proxy = await Proxy.deploy(
  implementation.address,
  NFTSale.interface.encodeFunctionData("initialize", [
    nftContractAddress,  // ERC-721 contract address
    priceInWei,          // Price per NFT in wei
    maxSupply,           // Total NFTs for sale
    maxPerWallet,        // Max NFTs per wallet
    startingTokenId,     // First token ID to sell
    initialAdmin         // Admin address
  ])
);
const contract = NFTSale.attach(proxy.address);


```

#### Initialization Parameters

- `_nftContract`: Address of the ERC-721 NFT contract.
- `_price`: Price per NFT (in wei).
- `_maxSupply`: Total number of NFTs available.
- `_maxPerWallet`: Max NFTs a wallet can buy.
- `_startingTokenId`: First token ID for sale.
- `initialAdmin`: Address granted `ADMIN_ROLE`.

### Key Functions

#### Admin Functions

- **`startSale()`**
  - Unpauses the contract and sets the sale start time to the current timestamp.
- **`setPrice(uint256 _newPrice)`**
  - Updates the NFT price.
- **`setMerkleRoot(bytes32 _merkleRoot)`**
  - Sets or updates the whitelist Merkle root.
- **`pause()`**
  - Pauses the contract, stopping purchases.
- **`unpause()`**
  - Resumes the contract, allowing purchases.
- **`withdraw()`**
  - Sends the contract's ETH balance to the calling admin.
- **`upgradeTo(address newImplementation)`**
  - Upgrades to a new contract version (UUPS).

#### User Functions

- **`buyNFT(bytes32[] calldata merkleProof)`**
  - Buys the next available NFT. Requires a Merkle proof if whitelisting is enabled. Send the exact ETH amount.

#### View Functions

- **`getNextTokenId()`**
  - Returns the next token ID to be sold.
- **`getBalance()`**
  - Returns the contract's ETH balance.
- **`purchases(address account)`**
  - Returns the number of NFTs bought by an address.

## How to Use the Contract

1. **Deploy and Initialize**

   - Deploy the implementation and proxy contracts with the required parameters.

2. **Transfer NFTs**

   - Transfer NFTs (from `startingTokenId` to `startingTokenId + maxSupply - 1`) to the proxy contract.

3. **Set Up Whitelist (Optional)**

   - Generate a Merkle root from whitelisted addresses.
   - Call `setMerkleRoot` to enable whitelisting.

4. **Start the Sale**

   - Call `startSale` to unpause and begin the sale.

5. **Purchase NFTs**

   - Users call `buyNFT` with the correct ETH amount and, if needed, a Merkle proof.

6. **Manage the Sale**

   - Admins can pause, unpause, adjust the price, or withdraw ETH.

7. **Upgrade (Optional)**
   - Deploy a new implementation and call `upgradeTo` to update the contract.

## Security Considerations

- **Pre-Minted NFTs**
  - Ensure all NFTs are minted and transferred to the contract before starting the sale.
- **Admin Security**
  - Protect `ADMIN_ROLE` addresses, as they control critical functions.
- **Whitelisting**
  - Update the Merkle root carefully to avoid locking out users.
- **Upgrades**
  - Only append new variables to the storage struct to avoid breaking the layout.
- **ETH Handling**
  - Excess ETH sent during purchases is refunded automatically.
