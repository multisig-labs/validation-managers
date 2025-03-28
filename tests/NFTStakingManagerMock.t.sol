// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

import { Base } from "./utils/Base.sol";

import { ERC721Mock } from "../contracts/mocks/ERC721Mock.sol";
import { NFTStakingManager, NFTStakingManagerSettings } from "../contracts/NFTStakingManager.sol";
import { IWarpMessenger, WarpMessage } from "./utils/IWarpMessenger.sol";

import { console2 } from "forge-std-1.9.6/src/console2.sol";
import { ERC1967Proxy } from "@openzeppelin-contracts-5.2.0/proxy/ERC1967/ERC1967Proxy.sol";
import { PChainOwner } from "icm-contracts-8817f47/contracts/validator-manager/ACP99Manager.sol";

contract MockValidatorManager {
  mapping(bytes32 nodeIDHash => bool created) public created;
  mapping(bytes32 nodeIDHash => bool validating) public validating;

  bytes32 public lastNodeID;

  function initiateValidatorRegistration(
    bytes memory nodeID,
    bytes memory, //bls public key
    uint64, // registration expiry
    PChainOwner memory, // remaining balance owner
    PChainOwner memory, // disable owner
    uint64 // weight
  ) external returns (bytes32) {
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

  function test_initiateValidatorRegistration() public {
    address validator = getActor("Validator");
    nft.mint(validator, 1);

    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = 1;

    vm.startPrank(validator);
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

  function test_initiateValidatorRegistration_twice() public {
    address validator = getActor("Validator");
    uint256 tokenId = 1;
    _initiateValidatorRegistration(validator, tokenId);

    assertEq(nft.balanceOf(validator), tokenId);
    assertEq(validatorManager.created(keccak256(DEFAULT_NODE_ID)), true);

    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = tokenId;

    vm.startPrank(validator);
    vm.expectRevert(abi.encodeWithSelector(NFTStakingManager.TokenAlreadyLocked.selector, tokenId));
    nftStakingManager.initiateValidatorRegistration(
      DEFAULT_NODE_ID,
      DEFAULT_BLS_PUBLIC_KEY,
      DEFAULT_P_CHAIN_OWNER,
      DEFAULT_P_CHAIN_OWNER,
      tokenIds
    );
    vm.stopPrank();
  }
  
  function test_completeValidatorRegistration() public {
    address validator = getActor("Validator");
    uint256 tokenId = 1;
    _initiateValidatorRegistration(validator, tokenId);
    
    nftStakingManager.completeValidatorRegistration(0);
    vm.stopPrank();

    assertEq(validatorManager.validating(keccak256(DEFAULT_NODE_ID)), true);
    assertEq(nftStakingManager.getCurrentTotalStakedLicenses(), 1);
  }

  // this test depends on the error from validatormanager
  function test_completeValidatorRegistration_twice() public {
    address validator = getActor("Validator");
    uint256 tokenId = 1;

    _initiateValidatorRegistration(validator, tokenId);
    _completeValidatorRegistration(validator, tokenId);
  }
  
  function _initiateValidatorRegistration(address validator, uint256 tokenId) internal {
    nft.mint(validator, tokenId);
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = tokenId;

    vm.startPrank(validator);
    nftStakingManager.initiateValidatorRegistration(
      DEFAULT_NODE_ID,
      DEFAULT_BLS_PUBLIC_KEY,
      DEFAULT_P_CHAIN_OWNER,
      DEFAULT_P_CHAIN_OWNER,
      tokenIds
    );
    vm.stopPrank();
  }
  
  function _completeValidatorRegistration(address validator, uint256 tokenId) internal {
    vm.startPrank(validator);
    nftStakingManager.completeValidatorRegistration(0);
    vm.stopPrank();
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
