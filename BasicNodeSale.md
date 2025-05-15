# BasicLicenseSale Contract Documentation

## Overview
The BasicLicenseSale contract manages the sale of licenses using USDC as payment, with configurable limits and whitelist functionality.

> **Security Note**: BasicLicenseSale.sol has not been audited and is provided "as is," without any express or implied warranties, including but not limited to warranties of merchantability, fitness for a particular purpose, or non-infringement. Projects must independently test, verify, and validate the code before use and assume full responsibility and all risks associated with its deployment. The design is based on [this contract](https://snowtrace.io/address/0xfDac2418cea741a14C95e1D157D5dEeD3778ABE7/contract/43114/code), originally used for the CX-Chain node sale.

## Core Features
- License sales management with USDC payments
- Configurable purchase limits per address
- Whitelist functionality for access control
- Fund collection and treasury management

## Contract Details

### Initialization Parameters
The following parameters must be set during contract deployment:
- `treasury`: Address where all collected funds will be transferred
  > **Security Note**: Ensure this is a secure, multi-sig wallet or similar secure address
- `usdc`: USDC token contract address
  - Avalanche Mainnet: `0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E`
  - Avalanche Testnet: `0x5425890298aed601595a70AB815c96711a31Bc65`


### State Variables
> **Important**: Before deployment, customize these values according to your project's specific requirements:
> - Adjust price based on your license valuation
> - Set appropriate limits for your use case
> - Configure whitelist settings as needed

- `price`: 0.01 USDC per license (10,000 with 6 decimals)
- `maxLicenses`: 250 licenses per address limit
- `maxTotalSupply`: 1000 total licenses limit
- `supply`: tracks total licenses sold
- `salesActive`: controls if sales are enabled
- `isWhitelistEnabled`: controls whitelist functionality

### Storage Structure
- `buyers[]`: array of all addresses that have purchased licenses
- `licensesPurchased`: mapping of address to number of licenses purchased
- `whitelist`: mapping of address to whitelist status

### Main Functions

#### Purchase
- `buy(uint256 licenseAmount)`: Purchase licenses with USDC
  - Checks whitelist, limits, and USDC balance/allowance

#### Admin Controls
- `setLicensePrice`: Update license price
- `setMaxLicensesPerAddress`: Update per-address limit
- `setMaxTotalSupply`: Update total supply limit
- `setWhitelistEnabled`: Toggle whitelist
- `startLicenseSales`/`stopLicenseSales`: Control sales status
- `withdrawToTreasury`: Withdraw collected USDC

#### Whitelist Management
- `addToWhitelist`: Add address to whitelist
- `removeFromWhitelist`: Remove address from whitelist

#### View Functions
- `getAllBuyers`: Get all buyers and their license counts
- `licensesPurchased`: Get licenses purchased by an address (public mapping)
- `whitelist`: Check whitelist status (public mapping)

### Security Features
- Uses `SafeERC20` for USDC transfers
- Implements `ReentrancyGuard`
- Owner-only admin functions
- Whitelist system for access control
- Configurable limits and controls

### Events
- `LicensePurchased`: Emitted on license purchase
- `PriceUpdated`: Emitted on price change
- `SalesStatusChanged`: Emitted on sales status change
- `WhitelistStatusChanged`: Emitted on whitelist status change
- `MaxLicensesUpdated`: Emitted on max licenses limit change
- `MaxTotalSupplyUpdated`: Emitted on total supply limit change

---

The contract is designed to be secure, flexible, and gas-efficient, with clear separation between user and admin functions.
