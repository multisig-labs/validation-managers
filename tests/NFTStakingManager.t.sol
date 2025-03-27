// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

import {ERC721Mock} from "../contracts/mocks/ERC721Mock.sol";
import {ERC1967Proxy} from "@openzeppelin-contracts-5.2.0/proxy/ERC1967/ERC1967Proxy.sol";

import {NFTStakingManager, NFTStakingManagerSettings} from "../contracts/NFTStakingManager.sol";
import {Base} from "./utils/Base.sol";
import {console} from "forge-std-1.9.6/src/console.sol";

import {ICMInitializable} from "icm-contracts-8817f47/contracts/utilities/ICMInitializable.sol";

import {PChainOwner} from "icm-contracts-8817f47/contracts/validator-manager/ACP99Manager.sol";
import {ValidatorManager, ValidatorManagerSettings} from "icm-contracts-8817f47/contracts/validator-manager/ValidatorManager.sol";

contract NFTStakingManagerTest is Base {
  uint64 public constant DEFAULT_CHURN_PERIOD = 1 hours;
  uint8 public constant DEFAULT_MAXIMUM_CHURN_PERCENTAGE = 20;
  bytes32 public constant DEFAULT_SUBNET_ID = bytes32(hex"1234567812345678123456781234567812345678123456781234567812345678");
  bytes public constant DEFAULT_BLS_PUBLIC_KEY =
    bytes(hex"123456781234567812345678123456781234567812345678123456781234567812345678123456781234567812345678");
  bytes public constant DEFAULT_NODE_ID = bytes(hex"1234123412341234123412341234123412341234");
  PChainOwner public DEFAULT_P_CHAIN_OWNER;

  ERC721Mock public nft;
  ValidatorManager public validatorManager;
  NFTStakingManager public nftStakingManager;
  address public admin;
  address public deployer;

  function setUp() public override {
    super.setUp();
    admin = getActor("Admin");
    deployer = getActor("Deployer");

    address[] memory addresses = new address[](1);
    addresses[0] = 0x1234567812345678123456781234567812345678;
    DEFAULT_P_CHAIN_OWNER = PChainOwner({threshold: 1, addresses: addresses});

    vm.startPrank(deployer);

    nft = new ERC721Mock("NFT License", "NFTL");

    ValidatorManager vmImpl = new ValidatorManager(ICMInitializable.Disallowed);
    ERC1967Proxy vmProxy = new ERC1967Proxy(address(vmImpl), abi.encodeCall(ValidatorManager.initialize, _defaultValidatorManagerSettings(deployer)));
    validatorManager = ValidatorManager(address(vmProxy));

    NFTStakingManager nftImpl = new NFTStakingManager();
    ERC1967Proxy nftProxy = new ERC1967Proxy(
      address(nftImpl), abi.encodeCall(NFTStakingManager.initialize, _defaultNFTStakingManagerSettings(address(validatorManager), address(nft)))
    );
    nftStakingManager = NFTStakingManager(address(nftProxy));

    validatorManager.transferOwnership(address(nftStakingManager));

    vm.stopPrank();
  }

  function test_Scenario1() public {
    address validator = getActor("Validator");
    nft.mint(validator, 1);
    vm.startPrank(validator);
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = 1;
    nftStakingManager.initiateValidatorRegistration(DEFAULT_NODE_ID, DEFAULT_BLS_PUBLIC_KEY, DEFAULT_P_CHAIN_OWNER, DEFAULT_P_CHAIN_OWNER, tokenIds);
    vm.stopPrank();
  }

  function _defaultValidatorManagerSettings(address admin_) internal pure returns (ValidatorManagerSettings memory) {
    return ValidatorManagerSettings({
      admin: admin_,
      subnetID: DEFAULT_SUBNET_ID,
      churnPeriodSeconds: DEFAULT_CHURN_PERIOD,
      maximumChurnPercentage: DEFAULT_MAXIMUM_CHURN_PERCENTAGE
    });
  }

  function _defaultNFTStakingManagerSettings(address validatorManager_, address license_) internal view returns (NFTStakingManagerSettings memory) {
    return NFTStakingManagerSettings({
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
