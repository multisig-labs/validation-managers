// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

import { Base } from "./utils/Base.sol";

import { ERC721Mock } from "../contracts/mocks/ERC721Mock.sol";
import { NFTStakingManager, NFTStakingManagerSettings } from "../contracts/NFTStakingManager.sol";
import { IWarpMessenger, WarpMessage } from "./utils/IWarpMessenger.sol";

import { console } from "forge-std-1.9.6/src/console.sol";
import { console2 } from "forge-std-1.9.6/src/console2.sol";

import { ERC1967Proxy } from "@openzeppelin-contracts-5.2.0/proxy/ERC1967/ERC1967Proxy.sol";

import { PChainOwner, ConversionData, InitialValidator } from "icm-contracts-8817f47/contracts/validator-manager/ACP99Manager.sol";
import { ValidatorManager, ValidatorManagerSettings } from "icm-contracts-8817f47/contracts/validator-manager/ValidatorManager.sol";
import { ACP99Manager } from "icm-contracts-8817f47/contracts/validator-manager/ACP99Manager.sol";

import { ValidatorManagerTest } from "icm-contracts-8817f47/contracts/validator-manager/tests/ValidatorManagerTests.t.sol";

contract MockValidatorManager {
    mapping(bytes32 nodeIDHash => bool created) public created;
    mapping(bytes32 nodeIDHash => bool validating) public validating;
    
    bytes32 public lastNodeID;

  function initiateValidatorRegistration(
    bytes memory nodeID,
    bytes memory blsPublicKey,
    uint64 registrationExpiry,
    PChainOwner memory remainingBalanceOwner,
    PChainOwner memory disableOwner,
    uint64 weight
  ) public returns (bytes32) {
    lastNodeID = keccak256(nodeID);
    created[lastNodeID] = true;
    return lastNodeID;
  }
  
  function completeValidatorRegistration(uint32) external returns (bytes32) {
    validating[lastNodeID] = true;
    created[lastNodeID] = false;
    return lastNodeID;
  }
}

contract NFTStakingManagerTest is Base {
  ERC721Mock public nft;
  MockValidatorManager public validatorManager;
  NFTStakingManager public nftStakingManager;

  address public admin;
  address public deployer;
  
  PChainOwner public DEFAULT_P_CHAIN_OWNER;
  bytes public constant DEFAULT_NODE_ID = bytes(hex"1234123412341234123412341234123412341234");

  bytes public constant DEFAULT_BLS_PUBLIC_KEY =
    bytes(
      hex"123456781234567812345678123456781234567812345678123456781234567812345678123456781234567812345678"
    );
  function setUp() public override {
    admin = getActor("Admin");
    deployer = getActor("Deployer");

    address[] memory addresses = new address[](1);
    addresses[0] = 0x1234567812345678123456781234567812345678;
    DEFAULT_P_CHAIN_OWNER = PChainOwner({ threshold: 1, addresses: addresses });

    vm.startPrank(deployer);

    validatorManager = new MockValidatorManager();

    nft = new ERC721Mock("NFT License", "NFTL");

    NFTStakingManager nftImpl = new NFTStakingManager();
    ERC1967Proxy nftProxy = new ERC1967Proxy(
      address(nftImpl),
      abi.encodeCall(
        NFTStakingManager.initialize,
        _defaultNFTStakingManagerSettings(address(validatorManager), address(nft))
      )
    );
    nftStakingManager = NFTStakingManager(address(nftProxy));

    vm.stopPrank();
  }

  function test_Scenario1() public {
    address validator = getActor("Validator");
    nft.mint(validator, 1);
    
    vm.startPrank(validator);
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = 1;
    nftStakingManager.initiateValidatorRegistration(
      DEFAULT_NODE_ID,
      DEFAULT_BLS_PUBLIC_KEY,
      DEFAULT_P_CHAIN_OWNER,
      DEFAULT_P_CHAIN_OWNER,
      tokenIds
    );
    vm.stopPrank();
    
    assertEq(nft.balanceOf(validator), 1);
    assertEq(validatorManager.created(keccak256(DEFAULT_NODE_ID)), true);
  }

  function _defaultNFTStakingManagerSettings(
    address validatorManager_,
    address license_
  ) internal view returns (NFTStakingManagerSettings memory) {
    return
      NFTStakingManagerSettings({
        validatorManager: validatorManager_,
        license: license_,
        initialEpochTimestamp: uint32(block.timestamp),
        epochDuration: 1 days,
        licenseWeight: 1000,
        epochRewards: 1000 ether,
        maxLicensesPerValidator: 10
      });
  }
}
