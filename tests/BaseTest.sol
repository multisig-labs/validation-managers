// SPDX-License-Identifier: Ecosystem

pragma solidity 0.8.25;

import {ConversionData, InitialValidator, PChainOwner} from "@avalabs/icm-contracts/validator-manager/interfaces/IValidatorManager.sol";
import {Test} from "@forge-std/Test.sol";
import "@forge-std/console2.sol";

import {MockWarpMessenger, WarpMessage} from "../contracts/mocks/MockWarpMessenger.sol";
import {MockNativeMinter} from "../contracts/mocks/MockNativeMinter.sol";

contract BaseTest is Test {
  uint256 private randNonce = 0;
  uint160 private actorCounter = 0;
  bytes32 public constant DEFAULT_BLOCKCHAIN_ID = bytes32(keccak256("test_chain"));
  bytes32 public constant DEFAULT_UPTIME_BLOCKCHAIN_ID = bytes32(keccak256("test_chain"));
  bytes32 public constant DEFAULT_SUBNET_ID = bytes32(hex"1234567812345678123456781234567812345678123456781234567812345678");
  bytes public constant DEFAULT_INITIAL_VALIDATOR_NODE_ID_1 = bytes(hex"2345678123456781234567812345678123456781234567812345678123456781");
  bytes public constant DEFAULT_INITIAL_VALIDATOR_NODE_ID_2 = bytes(hex"1345678123456781234567812345678123456781234567812345678123456781");
  bytes public constant DEFAULT_BLS_PUBLIC_KEY =
    bytes(hex"123456781234567812345678123456781234567812345678123456781234567812345678123456781234567812345678");
  uint64 public constant DEFAULT_WEIGHT = 1e6;
  // Set the default weight to 1e10 to avoid churn issues
  uint64 public constant DEFAULT_INITIAL_VALIDATOR_WEIGHT = DEFAULT_WEIGHT * 1e4;
  uint64 public constant DEFAULT_MINIMUM_STAKE_DURATION = 24 hours;

  function makeDefaultConversionData(address validatorManagerAddress) internal pure returns (ConversionData memory) {
    InitialValidator[] memory initialValidators = new InitialValidator[](2);
    // The first initial validator has a high weight relative to the default PoS validator weight to avoid churn issues
    initialValidators[0] =
      InitialValidator({nodeID: DEFAULT_INITIAL_VALIDATOR_NODE_ID_1, weight: DEFAULT_INITIAL_VALIDATOR_WEIGHT, blsPublicKey: DEFAULT_BLS_PUBLIC_KEY});
    // The second initial validator has a low weight so that it can be safely removed in tests
    initialValidators[1] =
      InitialValidator({nodeID: DEFAULT_INITIAL_VALIDATOR_NODE_ID_2, weight: DEFAULT_WEIGHT, blsPublicKey: DEFAULT_BLS_PUBLIC_KEY});
    return ConversionData({
      l1ID: DEFAULT_SUBNET_ID,
      validatorManagerBlockchainID: DEFAULT_BLOCKCHAIN_ID,
      validatorManagerAddress: validatorManagerAddress,
      initialValidators: initialValidators
    });
  }

  function makePChainOwner(address owner) internal pure returns (PChainOwner memory) {
    address[] memory addresses = new address[](1);
    addresses[0] = address(owner);
    return PChainOwner({threshold: 1, addresses: addresses});
  }

  function makeWarpMock() internal returns (MockWarpMessenger) {
    // First deploy the contract normally to get its bytecode
    MockWarpMessenger tempWarp = new MockWarpMessenger();
    // Choose your desired address (warp precompile)
    address warpAddress = address(0x0200000000000000000000000000000000000005);
    // Get the runtime bytecode
    bytes memory code = address(tempWarp).code;
    // Use vm.etch to deploy at specific address
    vm.etch(warpAddress, code);
    // Point the warp variable to the contract at the specific address
    MockWarpMessenger warp = MockWarpMessenger(warpAddress);
    warp.reset();
    return warp;
  }

  function makeNativeMinterMock() internal returns (MockNativeMinter) {
    // First deploy the contract normally to get its bytecode
    MockNativeMinter tempNativeMinter = new MockNativeMinter();
    // Choose your desired address (warp precompile)
    address nativeMinterAddress = address(0x0200000000000000000000000000000000000001);
    // Get the runtime bytecode
    bytes memory code = address(tempNativeMinter).code;
    // Use vm.etch to deploy at specific address
    vm.etch(nativeMinterAddress, code);
    // Point the warp variable to the contract at the specific address
    MockNativeMinter nativeMinter = MockNativeMinter(nativeMinterAddress);
    return nativeMinter;
  }

  function makeActor(string memory name) internal returns (address) {
    actorCounter++;
    address addr = address(uint160(0x50000 + actorCounter));
    vm.label(addr, name);
    return addr;
  }

  function randHash() internal returns (bytes32) {
    randNonce++;
    return keccak256(abi.encodePacked(randNonce, blockhash(block.timestamp)));
  }

  function randNodeID() internal returns (bytes memory) {
    return abi.encodePacked(randHash());
  }

  function randAddress() internal returns (address) {
    randNonce++;
    return address(uint160(uint256(randHash())));
  }

  function randUint(uint256 _modulus) internal returns (uint256) {
    randNonce++;
    return uint256(randHash()) % _modulus;
  }

  function randUintBetween(uint256 lowerBound, uint256 upperBound) internal returns (uint256) {
    randNonce++;
    uint256 bound = uint256(randHash()) % (upperBound - lowerBound);
    uint256 randomNum = bound + lowerBound;
    return randomNum;
  }
}
