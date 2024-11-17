// SPDX-License-Identifier: Ecosystem

pragma solidity 0.8.25;

import "forge-std/console2.sol";
import {Test} from "@forge-std/Test.sol";
import {ERC20TokenStakingManager} from "../ERC20TokenStakingManager.sol";
import {IERC20} from "@openzeppelin/contracts@5.0.2/token/ERC20/IERC20.sol";
import {IERC20Mintable} from "../interfaces/IERC20Mintable.sol";
import {ICMInitializable} from "../../utilities/ICMInitializable.sol";
import {
    ValidatorManagerSettings,
    ValidatorRegistrationInput,
    PChainOwner,
    ConversionData,
    InitialValidator,
    IValidatorManager
} from "../interfaces/IValidatorManager.sol";
import {PoSValidatorManagerSettings} from "../interfaces/IPoSValidatorManager.sol";
import {SafeERC20} from "@openzeppelin/contracts@5.0.2/token/ERC20/utils/SafeERC20.sol";
import {ExampleERC20} from "@mocks/ExampleERC20.sol";
import {ExampleRewardCalculator} from "../ExampleRewardCalculator.sol";
import {IRewardCalculator} from "../interfaces/IRewardCalculator.sol";
import {MockWarpMessenger, WarpMessage} from "@mocks/MockWarpMessenger.sol";
import {ValidatorMessages} from "../ValidatorMessages.sol";

contract BlackBoxERC20Tests is Test {
    using SafeERC20 for IERC20Mintable;

    // ValidatorManagerTest constants
    bytes32 public constant DEFAULT_SUBNET_ID =
        bytes32(hex"1234567812345678123456781234567812345678123456781234567812345678");
    bytes public constant DEFAULT_NODE_ID =
        bytes(hex"1234567812345678123456781234567812345678123456781234567812345678");
    bytes public constant DEFAULT_INITIAL_VALIDATOR_NODE_ID_1 =
        bytes(hex"2345678123456781234567812345678123456781234567812345678123456781");
    bytes public constant DEFAULT_INITIAL_VALIDATOR_NODE_ID_2 =
        bytes(hex"1345678123456781234567812345678123456781234567812345678123456781");
    bytes public constant DEFAULT_BLS_PUBLIC_KEY = bytes(
        hex"123456781234567812345678123456781234567812345678123456781234567812345678123456781234567812345678"
    );

    uint64 public constant DEFAULT_WEIGHT = 1e6;
    // Set the default weight to 1e10 to avoid churn issues
    uint64 public constant DEFAULT_INITIAL_VALIDATOR_WEIGHT = DEFAULT_WEIGHT * 1e4;
    uint256 public constant DEFAULT_MINIMUM_STAKE_AMOUNT = 20e12;
    uint256 public constant DEFAULT_MAXIMUM_STAKE_AMOUNT = 1e22;
    uint64 public constant DEFAULT_CHURN_PERIOD = 1 hours;
    uint8 public constant DEFAULT_MAXIMUM_CHURN_PERCENTAGE = 20;
    uint64 public constant DEFAULT_EXPIRY = 1000;
    uint8 public constant DEFAULT_MAXIMUM_HOURLY_CHURN = 0;
    uint64 public constant DEFAULT_REGISTRATION_TIMESTAMP = 1000;
    uint256 public constant DEFAULT_STARTING_TOTAL_WEIGHT = 1e10 + DEFAULT_WEIGHT;
    uint64 public constant DEFAULT_MINIMUM_VALIDATION_DURATION = 24 hours;
    uint64 public constant DEFAULT_COMPLETION_TIMESTAMP = 100_000;

    // ERC20TokenStakingManagerTest constants
    uint64 public constant DEFAULT_UPTIME = uint64(100);
    uint64 public constant DEFAULT_DELEGATOR_WEIGHT = uint64(1e5);
    uint64 public constant DEFAULT_DELEGATOR_INIT_REGISTRATION_TIMESTAMP =
        DEFAULT_REGISTRATION_TIMESTAMP + DEFAULT_EXPIRY;
    uint64 public constant DEFAULT_DELEGATOR_COMPLETE_REGISTRATION_TIMESTAMP =
        DEFAULT_DELEGATOR_INIT_REGISTRATION_TIMESTAMP + DEFAULT_EXPIRY;
    uint64 public constant DEFAULT_DELEGATOR_END_DELEGATION_TIMESTAMP =
        DEFAULT_DELEGATOR_COMPLETE_REGISTRATION_TIMESTAMP + DEFAULT_MINIMUM_STAKE_DURATION;
    address public constant DEFAULT_DELEGATOR_ADDRESS =
        address(0x1234123412341234123412341234123412341234);
    address public constant DEFAULT_VALIDATOR_OWNER_ADDRESS =
        address(0x2345234523452345234523452345234523452345);
    uint64 public constant DEFAULT_REWARD_RATE = uint64(10);
    uint64 public constant DEFAULT_MINIMUM_STAKE_DURATION = 24 hours;
    uint16 public constant DEFAULT_MINIMUM_DELEGATION_FEE_BIPS = 100;
    uint16 public constant DEFAULT_DELEGATION_FEE_BIPS = 150;
    uint8 public constant DEFAULT_MAXIMUM_STAKE_MULTIPLIER = 4;
    uint256 public constant DEFAULT_WEIGHT_TO_VALUE_FACTOR = 1e12;
    uint256 public constant SECONDS_IN_YEAR = 31536000;

    ERC20TokenStakingManager public app;
    IERC20Mintable public token;
    IRewardCalculator public rewardCalculator;
    MockWarpMessenger public warp;
    PChainOwner public DEFAULT_P_CHAIN_OWNER;

    function setUp() public {
        _setUpPChainOwner();
        _setUpWarpMock();
        app = new ERC20TokenStakingManager(ICMInitializable.Allowed);
        token = new ExampleERC20();
        rewardCalculator = new ExampleRewardCalculator(DEFAULT_REWARD_RATE);

        app.initialize(
            PoSValidatorManagerSettings({
                baseSettings: ValidatorManagerSettings({
                    subnetID: DEFAULT_SUBNET_ID,
                    churnPeriodSeconds: DEFAULT_CHURN_PERIOD,
                    maximumChurnPercentage: DEFAULT_MAXIMUM_CHURN_PERCENTAGE
                }),
                minimumStakeAmount: DEFAULT_MINIMUM_STAKE_AMOUNT,
                maximumStakeAmount: DEFAULT_MAXIMUM_STAKE_AMOUNT,
                minimumStakeDuration: DEFAULT_MINIMUM_STAKE_DURATION,
                minimumDelegationFeeBips: DEFAULT_MINIMUM_DELEGATION_FEE_BIPS,
                maximumStakeMultiplier: DEFAULT_MAXIMUM_STAKE_MULTIPLIER,
                weightToValueFactor: DEFAULT_WEIGHT_TO_VALUE_FACTOR,
                rewardCalculator: rewardCalculator
            }),
            token
        );

        ConversionData memory conversionData = _defaultConversionData();
        bytes memory packedConversionData = ValidatorMessages.packConversionData(conversionData);
        bytes32 conversionID = sha256(packedConversionData);
        bytes memory conversionMessage =
            ValidatorMessages.packSubnetToL1ConversionMessage(conversionID);
        (uint32 index,) = warp.setWarpMessageFromP(conversionMessage);
        app.initializeValidatorSet(conversionData, index);
        warp.reset();
    }

    function testStake() public {
        uint256 stakeAmount = 1 ether;
        // Mint tokens to the test contract
        token.mint(address(this), stakeAmount);

        // Approve the staking manager to spend tokens
        token.approve(address(app), stakeAmount);
        bytes32 validationID = app.initializeValidatorRegistration(
            ValidatorRegistrationInput({
                nodeID: DEFAULT_NODE_ID,
                blsPublicKey: DEFAULT_BLS_PUBLIC_KEY,
                registrationExpiry: DEFAULT_EXPIRY,
                remainingBalanceOwner: DEFAULT_P_CHAIN_OWNER,
                disableOwner: DEFAULT_P_CHAIN_OWNER
            }),
            DEFAULT_DELEGATION_FEE_BIPS,
            DEFAULT_MINIMUM_STAKE_DURATION,
            stakeAmount
        );
    }

    function testWarpMock() public {
        bytes memory payloadBytes_1 = abi.encode("payload_1");
        bytes32 messageID_1 = warp.sendWarpMessage(payloadBytes_1);

        bytes memory payloadBytes_2 = abi.encode("payload_2");
        bytes32 messageID_2 = warp.sendWarpMessage(payloadBytes_2);

        // Get directly from storage
        (bytes32 sourceChainID, address sender, bytes memory payload) = warp.messages(messageID_1);
        assertEq(sourceChainID, warp.getBlockchainID());
        assertEq(sender, address(this));
        assertEq(payload, payloadBytes_1);

        // Get from getVerifiedWarpMessage
        (WarpMessage memory message, bool valid) = warp.getVerifiedWarpMessage(0);
        assertEq(valid, true);
        assertEq(message.sourceChainID, warp.getBlockchainID());
        assertEq(message.originSenderAddress, address(this));
        assertEq(message.payload, payloadBytes_1);

        // Get directly from storage
        (sourceChainID, sender, payload) = warp.messages(messageID_2);
        assertEq(sourceChainID, warp.getBlockchainID());
        assertEq(sender, address(this));
        assertEq(payload, payloadBytes_2);

        (message, valid) = warp.getVerifiedWarpMessage(1);
        assertEq(valid, true);
        assertEq(message.sourceChainID, warp.getBlockchainID());
        assertEq(message.originSenderAddress, address(this));
        assertEq(message.payload, payloadBytes_2);

        (message, valid) = warp.getVerifiedWarpMessage(2);
        assertEq(valid, false);
    }

    function _defaultConversionData() internal view returns (ConversionData memory) {
        InitialValidator[] memory initialValidators = new InitialValidator[](2);
        // The first initial validator has a high weight relative to the default PoS validator weight
        // to avoid churn issues
        initialValidators[0] = InitialValidator({
            nodeID: DEFAULT_INITIAL_VALIDATOR_NODE_ID_1,
            weight: DEFAULT_INITIAL_VALIDATOR_WEIGHT,
            blsPublicKey: DEFAULT_BLS_PUBLIC_KEY
        });
        // The second initial validator has a low weight so that it can be safely removed in tests
        initialValidators[1] = InitialValidator({
            nodeID: DEFAULT_INITIAL_VALIDATOR_NODE_ID_2,
            weight: DEFAULT_WEIGHT,
            blsPublicKey: DEFAULT_BLS_PUBLIC_KEY
        });
        return ConversionData({
            subnetID: DEFAULT_SUBNET_ID,
            validatorManagerBlockchainID: warp.getBlockchainID(),
            validatorManagerAddress: address(app),
            initialValidators: initialValidators
        });
    }

    function _setUpPChainOwner() internal {
        address[] memory addresses = new address[](1);
        addresses[0] = address(this);
        DEFAULT_P_CHAIN_OWNER = PChainOwner({threshold: 1, addresses: addresses});
    }

    function _setUpWarpMock() internal {
        // First deploy the contract normally to get its bytecode
        MockWarpMessenger tempWarp = new MockWarpMessenger();
        // Choose your desired address (warp precompile)
        address warpAddress = address(0x0200000000000000000000000000000000000005);
        // Get the runtime bytecode
        bytes memory code = address(tempWarp).code;
        // Use vm.etch to deploy at specific address
        vm.etch(warpAddress, code);
        // Point the warp variable to the contract at the specific address
        warp = MockWarpMessenger(warpAddress);
        warp.reset();
    }
}
