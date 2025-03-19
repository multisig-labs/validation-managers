// SPDX-License-Identifier: Ecosystem

pragma solidity 0.8.25;

import {BaseTest} from "./BaseTest.sol";

import {ICMInitializable} from "@avalabs/icm-contracts/utilities/ICMInitializable.sol";
import {ERC20TokenStakingManager} from "@avalabs/icm-contracts/validator-manager/ERC20TokenStakingManager.sol";

import {ExampleRewardCalculator} from "@avalabs/icm-contracts/validator-manager/ExampleRewardCalculator.sol";

import {ExampleERC20} from "../contracts/mocks/ExampleERC20.sol";

import {MockWarpMessenger, WarpMessage} from "../contracts/mocks/MockWarpMessenger.sol";
import {ValidatorMessages} from "@avalabs/icm-contracts/validator-manager/ValidatorMessages.sol";
import {IERC20Mintable} from "@avalabs/icm-contracts/validator-manager/interfaces/IERC20Mintable.sol";
import {PoSValidatorManagerSettings} from "@avalabs/icm-contracts/validator-manager/interfaces/IPoSValidatorManager.sol";
import {IRewardCalculator} from "@avalabs/icm-contracts/validator-manager/interfaces/IRewardCalculator.sol";
import {
  ConversionData,
  IValidatorManager,
  InitialValidator,
  PChainOwner,
  Validator,
  ValidatorManagerSettings,
  ValidatorRegistrationInput,
  ValidatorStatus
} from "@avalabs/icm-contracts/validator-manager/interfaces/IValidatorManager.sol";

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract BlackBoxERC20Tests is BaseTest {
  using SafeERC20 for IERC20Mintable;

  uint256 public constant DEFAULT_MINIMUM_STAKE_AMOUNT = 20e12;
  uint256 public constant DEFAULT_MAXIMUM_STAKE_AMOUNT = 1e22;
  uint8 public constant DEFAULT_MAXIMUM_CHURN_PERCENTAGE = 20;
  uint64 public constant DEFAULT_CHURN_PERIOD = 1 hours;

  // ERC20TokenStakingManagerTest constants
  uint64 public constant DEFAULT_REWARD_RATE = uint64(10);
  uint16 public constant DEFAULT_MINIMUM_DELEGATION_FEE_BIPS = 100;
  uint16 public constant DEFAULT_DELEGATION_FEE_BIPS = 150;
  uint8 public constant DEFAULT_MAXIMUM_STAKE_MULTIPLIER = 4;
  uint256 public constant DEFAULT_WEIGHT_TO_VALUE_FACTOR = 1e12;

  ERC20TokenStakingManager public app;
  ExampleERC20 public token;
  IRewardCalculator public rewardCalculator;
  MockWarpMessenger public warp;

  function setUp() public {
    warp = makeWarpMock();
    token = new ExampleERC20();
    app = new ERC20TokenStakingManager(ICMInitializable.Allowed);
    rewardCalculator = new ExampleRewardCalculator(DEFAULT_REWARD_RATE);

    app.initialize(
      PoSValidatorManagerSettings({
        baseSettings: ValidatorManagerSettings({
          l1ID: DEFAULT_SUBNET_ID,
          churnPeriodSeconds: DEFAULT_CHURN_PERIOD,
          maximumChurnPercentage: DEFAULT_MAXIMUM_CHURN_PERCENTAGE
        }),
        minimumStakeAmount: DEFAULT_MINIMUM_STAKE_AMOUNT,
        maximumStakeAmount: DEFAULT_MAXIMUM_STAKE_AMOUNT,
        minimumStakeDuration: DEFAULT_MINIMUM_STAKE_DURATION,
        minimumDelegationFeeBips: DEFAULT_MINIMUM_DELEGATION_FEE_BIPS,
        maximumStakeMultiplier: DEFAULT_MAXIMUM_STAKE_MULTIPLIER,
        weightToValueFactor: DEFAULT_WEIGHT_TO_VALUE_FACTOR,
        rewardCalculator: rewardCalculator,
        uptimeBlockchainID: DEFAULT_UPTIME_BLOCKCHAIN_ID
      }),
      token
    );

    ConversionData memory conversionData = makeDefaultConversionData(address(app));
    bytes memory packedConversionData = ValidatorMessages.packConversionData(conversionData);
    bytes32 conversionID = sha256(packedConversionData);
    bytes memory conversionMessage = ValidatorMessages.packSubnetToL1ConversionMessage(conversionID);
    // Simulate a message being sent from the P chain
    (uint32 index,) = warp.setWarpMessageFromP(conversionMessage);
    app.initializeValidatorSet(conversionData, index);
    warp.reset(); // clear out the warp messages
  }

  function testStakeERC20() public {
    PChainOwner memory pChainOwner = makePChainOwner(makeActor("pChainOwner"));
    uint64 registrationExpiry = uint64(block.timestamp) + 100;
    uint256 stakeAmount = 1 ether;
    token.mint(address(this), stakeAmount);
    token.approve(address(app), stakeAmount);

    bytes memory nodeID = randNodeID();

    bytes32 validationID = app.initializeValidatorRegistration(
      ValidatorRegistrationInput({
        nodeID: nodeID,
        blsPublicKey: DEFAULT_BLS_PUBLIC_KEY,
        registrationExpiry: registrationExpiry,
        remainingBalanceOwner: pChainOwner,
        disableOwner: pChainOwner
      }),
      DEFAULT_DELEGATION_FEE_BIPS,
      DEFAULT_MINIMUM_STAKE_DURATION,
      stakeAmount
    );

    // Check that the validator registration was started
    Validator memory validator = app.getValidator(validationID);
    assertEq(validator.nodeID, nodeID);
    assertEq(uint8(validator.status), uint8(ValidatorStatus.PendingAdded));

    // Simulate msg from PChain
    bytes memory packedValidatorRegMsg = ValidatorMessages.packL1ValidatorRegistrationMessage(validationID, true);
    (uint32 index,) = warp.setWarpMessageFromP(packedValidatorRegMsg);
    // Complete the validator registration
    app.completeValidatorRegistration(index);

    // Check that the validator registration was completed
    validator = app.getValidator(validationID);
    assertEq(uint8(validator.status), uint8(ValidatorStatus.Active));

    vm.warp(block.timestamp + DEFAULT_MINIMUM_STAKE_DURATION + 1);

    // Simulate uptime proof message from the EVM
    bytes memory packedUptimeProofMsg = ValidatorMessages.packValidationUptimeMessage(validationID, uint64(block.timestamp) - validator.startedAt);
    (index,) = warp.setWarpMessage(address(0), warp.getBlockchainID(), packedUptimeProofMsg);
    app.submitUptimeProof(validationID, index);

    app.initializeEndValidation(validationID, false, 0);
    validator = app.getValidator(validationID);
    assertEq(uint8(validator.status), uint8(ValidatorStatus.PendingRemoved));

    // Simulate msg from PChain (must be "invalid" now)
    packedValidatorRegMsg = ValidatorMessages.packL1ValidatorRegistrationMessage(validationID, false);
    (index,) = warp.setWarpMessageFromP(packedValidatorRegMsg);
    app.completeEndValidation(index);

    // Check that the validator was removed
    validator = app.getValidator(validationID);
    assertEq(uint8(validator.status), uint8(ValidatorStatus.Completed));

    // Check for stake and rewards
    assertGt(token.balanceOf(address(this)), stakeAmount);
  }
}
