# NFTStakingManager Test Structure

This directory contains the refactored test suite for the NFTStakingManager contract. The tests have been organized into focused, manageable files instead of one large monolithic test file.

## Structure

### Base Classes

- **`utils/Base.sol`** - Core test utilities and common setup
- **`utils/NFTStakingManagerBase.sol`** - NFTStakingManager-specific test base with:
  - Complete contract setup (NFTStakingManager, NodeLicense, mocks)
  - Helper methods for creating validators and delegations
  - Common test utilities and constants
  - Warp message mocking utilities

### Test Files

- **`NFTStakingManagerInitialization.t.sol`** - Contract initialization and settings tests
- **`NFTStakingManagerValidatorRegistration.t.sol`** - Validator registration tests
- **`NFTStakingManagerValidatorRemoval.t.sol`** - Validator removal tests  
- **`NFTStakingManagerDelegatorRegistration.t.sol`** - Delegator registration tests
- **`NFTStakingManagerDelegatorRemoval.t.sol`** - Delegator removal tests
- **`NFTStakingManagerProofProcessing.t.sol`** - Uptime proof processing tests
- **`NFTStakingManagerRewards.t.sol`** - Rewards minting and claiming tests
- **`NFTStakingManagerPrepayment.t.sol`** - Prepayment credit and delegation fee tests
- **`NFTStakingManagerNonce.t.sol`** - Nonce handling and delegation lifecycle tests

## Usage

### Running All Tests
```bash
forge test
```

### Running Tests for a Specific Area
```bash
# Validator registration tests only
forge test --match-contract NFTStakingManagerValidatorRegistrationTest

# Delegator registration tests only  
forge test --match-contract NFTStakingManagerDelegatorRegistrationTest
```

### Running a Specific Test
```bash
forge test --match-contract NFTStakingManagerValidatorRegistrationTest --match-test test_initiateValidatorRegistration
```

## Helper Methods Available in Base Class

All test files inherit from `NFTStakingManagerBase` which provides:

- `_createValidator()` - Creates a complete validator setup
- `_createDelegation()` - Creates delegations with various configurations
- `_processUptimeProof()` - Processes uptime proofs for testing
- `_mintOneReward()` - Mints rewards for testing
- `_warpToGracePeriod()` / `_warpAfterGracePeriod()` - Time manipulation utilities
- `_mockGetUptimeWarpMessage()` - Warp message mocking

## Adding New Tests

When adding new tests:

1. Inherit from `NFTStakingManagerBase`
2. Import any additional types needed from the main contract
3. Use the helper methods to set up test scenarios
4. Follow the existing naming conventions

Example:
```solidity
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

import { NFTStakingManagerBase } from "./utils/NFTStakingManagerBase.sol";
import { NFTStakingManager, ValidationInfoView } from "../contracts/NFTStakingManager.sol";

contract NFTStakingManagerNewFeatureTest is NFTStakingManagerBase {
  
  function test_newFeature() public {
    (bytes32 validationID, address validator) = _createValidator();
    // ... test implementation
  }
}
```
