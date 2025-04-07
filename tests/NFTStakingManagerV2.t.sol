// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

import { Base } from "./utils/Base.sol";

import {
  NFTStakingManager,
  NFTStakingManagerSettings,
  StakeInfo
} from "../contracts/NFTStakingManagerV2.sol";
import { ERC721Mock } from "../contracts/mocks/ERC721Mock.sol";
import { NativeMinterMock } from "../contracts/mocks/NativeMinterMock.sol";
import { IWarpMessenger, WarpMessage } from "./utils/IWarpMessenger.sol";

import { ERC1967Proxy } from "@openzeppelin-contracts-5.2.0/proxy/ERC1967/ERC1967Proxy.sol";
import { console2 } from "forge-std-1.9.6/src/console2.sol";
import { PChainOwner } from "icm-contracts-8817f47/contracts/validator-manager/ACP99Manager.sol";

contract MockValidatorManager {
  mapping(bytes32 nodeIDHash => bool created) public created;
  mapping(bytes32 nodeIDHash => bool validating) public validating;
  mapping(bytes32 nodeIDHash => bool pendingRemoval) public pendingRemoval;

  bytes32 public lastNodeID;

  uint256 private randNonce = 0;

  function initiateValidatorRegistration(
    bytes memory, // nodeID
    bytes memory, //bls public key
    uint64, // registration expiry
    PChainOwner memory, // remaining balance owner
    PChainOwner memory, // disable owner
    uint64 // weight
  ) external returns (bytes32) {
    lastNodeID = _getValidationID();
    created[lastNodeID] = true;
    return lastNodeID;
  }

  function completeValidatorRegistration(uint32) external returns (bytes32) {
    validating[lastNodeID] = true;
    created[lastNodeID] = false;
    return lastNodeID;
  }

  function initiateValidatorRemoval(bytes32 stakeID) external {
    lastNodeID = stakeID;
    pendingRemoval[stakeID] = true;
    validating[stakeID] = false;
  }

  function completeValidatorRemoval(uint32) external returns (bytes32) {
    pendingRemoval[lastNodeID] = false;
    return lastNodeID;
  }

  function _getValidationID() internal returns (bytes32) {
    randNonce++;
    return keccak256(abi.encodePacked(block.timestamp, randNonce, address(this)));
  }
}

contract NFTStakingManagerTest is Base {
  ERC721Mock public nft;
  ERC721Mock public hardwareNft;
  MockValidatorManager public validatorManager;
  NFTStakingManager public nftStakingManager;

  address public admin;
  address public deployer;

  uint256 public epochRewards = 1000 ether;
  uint16 public MAX_LICENSES_PER_VALIDATOR = 10;

  function setUp() public override {
    super.setUp();
    admin = getActor("Admin");
    deployer = getActor("Deployer");

    address[] memory addresses = new address[](1);
    addresses[0] = 0x1234567812345678123456781234567812345678;
    DEFAULT_P_CHAIN_OWNER = PChainOwner({ threshold: 1, addresses: addresses });

    vm.startPrank(deployer);

    validatorManager = new MockValidatorManager();

    nft = new ERC721Mock("NFT License", "NFTL");
    hardwareNft = new ERC721Mock("Hardware NFT License", "HARDNFTL");

    NFTStakingManager stakingManagerImpl = new NFTStakingManager();
    ERC1967Proxy stakingManagerProxy = new ERC1967Proxy(
      address(stakingManagerImpl),
      abi.encodeCall(
        NFTStakingManager.initialize,
        _defaultNFTStakingManagerSettings(
          address(validatorManager), address(nft), address(hardwareNft)
        )
      )
    );
    nftStakingManager = NFTStakingManager(address(stakingManagerProxy));

    NativeMinterMock nativeMinter = new NativeMinterMock();
    vm.etch(0x0200000000000000000000000000000000000001, address(nativeMinter).code);
    vm.stopPrank();
  }

  function _defaultNFTStakingManagerSettings(
    address validatorManager_,
    address license_,
    address hardwareLicense_
  ) internal view returns (NFTStakingManagerSettings memory) {
    return NFTStakingManagerSettings({
      validatorManager: validatorManager_,
      license: license_,
      hardwareLicense: hardwareLicense_,
      initialEpochTimestamp: uint32(block.timestamp),
      epochDuration: 1 days,
      licenseWeight: 1000,
      hardwareLicenseWeight: 1000000, // 1 million
      epochRewards: epochRewards,
      maxLicensesPerValidator: MAX_LICENSES_PER_VALIDATOR,
      requireHardwareTokenId: true
    });
  }

  function testv2_initiateValidatorRegistration() public {
    address validator = getActor("Validator");
    nft.mint(validator, 1);
    hardwareNft.mint(validator, 1);

    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = 1;

    uint256 hardwareTokenId = 1;

    vm.startPrank(validator);
    bytes32 stakeID = nftStakingManager.initiateValidatorRegistration(
      DEFAULT_NODE_ID,
      DEFAULT_BLS_PUBLIC_KEY,
      DEFAULT_P_CHAIN_OWNER,
      DEFAULT_P_CHAIN_OWNER,
      hardwareTokenId,
      tokenIds
    );
    vm.stopPrank();

    assertEq(nft.balanceOf(validator), 1);
    assertEq(hardwareNft.balanceOf(validator), 1);
    assertEq(validatorManager.created(stakeID), true);
  }

  //   function test_initiateValidatorRegistration() public {
  //     address validator = getActor("Validator");
  //     nft.mint(validator, 1);

  //     uint256[] memory tokenIds = new uint256[](1);
  //     tokenIds[0] = 1;

  //     vm.startPrank(validator);
  //     bytes32 stakeID = nftStakingManager.initiateValidatorRegistration(
  //       DEFAULT_NODE_ID,
  //       DEFAULT_BLS_PUBLIC_KEY,
  //       DEFAULT_P_CHAIN_OWNER,
  //       DEFAULT_P_CHAIN_OWNER,
  //       tokenIds
  //     );
  //     vm.stopPrank();

  //     assertEq(nft.balanceOf(validator), 1);
  //     assertEq(validatorManager.created(stakeID), true);
  //   }

  //   function test_initiateValidatorRegistration_twice() public {
  //     address validator = getActor("Validator");
  //     uint256 tokenId = 1;
  //     bytes32 stakeID = _initiateValidatorRegistration(validator, tokenId);

  //     assertEq(nft.balanceOf(validator), tokenId);
  //     assertEq(validatorManager.created(stakeID), true);

  //     uint256[] memory tokenIds = new uint256[](1);
  //     tokenIds[0] = tokenId;

  //     vm.startPrank(validator);
  //     vm.expectRevert(abi.encodeWithSelector(NFTStakingManager.TokenAlreadyLocked.selector, tokenId));
  //     nftStakingManager.initiateValidatorRegistration(
  //       DEFAULT_NODE_ID,
  //       DEFAULT_BLS_PUBLIC_KEY,
  //       DEFAULT_P_CHAIN_OWNER,
  //       DEFAULT_P_CHAIN_OWNER,
  //       tokenIds
  //     );
  //     vm.stopPrank();
  //   }

  //   function test_completeValidatorRegistration() public {
  //     address validator = getActor("Validator");
  //     uint256 tokenId = 1;
  //     bytes32 stakeID = _initiateValidatorRegistration(validator, tokenId);

  //     nftStakingManager.completeValidatorRegistration(0);
  //     vm.stopPrank();

  //     assertEq(validatorManager.validating(stakeID), true);
  //     assertEq(nftStakingManager.getCurrentTotalStakedLicenses(), 1);
  //   }

  //   function test_initiateValidatorRemoval() public {
  //     address validator = getActor("Validator");
  //     uint256 tokenId = 1;
  //     bytes32 stakeID = _initiateValidatorRegistration(validator, tokenId);
  //     _completeValidatorRegistration(validator);
  //     assertEq(nftStakingManager.getCurrentTotalStakedLicenses(), 1);

  //     vm.startPrank(validator);
  //     nftStakingManager.initiateValidatorRemoval(stakeID);
  //     vm.stopPrank();

  //     assertEq(nftStakingManager.getCurrentTotalStakedLicenses(), 0);
  //     assertEq(validatorManager.validating(stakeID), false);
  //   }

  //   function test_rewards() public {
  //     address validator = getActor("Validator");
  //     uint256 tokenId = 1;
  //     bytes32 stakeID1 = _initiateValidatorRegistration(validator, tokenId);
  //     _completeValidatorRegistration(validator);

  //     address validator2 = getActor("Validator2");
  //     uint256 tokenId2 = 2;
  //     bytes32 stakeID2 = _initiateValidatorRegistration(validator2, tokenId2);
  //     _completeValidatorRegistration(validator2);

  //     uint32 lastEpoch = nftStakingManager.getCurrentEpoch();

  //     vm.warp(block.timestamp + 1 days);
  //     nftStakingManager.rewardsSnapshot();

  //     bytes32[] memory stakeIds = new bytes32[](2);
  //     stakeIds[0] = stakeID1;
  //     stakeIds[1] = stakeID2;
  //     nftStakingManager.mintRewards(lastEpoch, stakeIds);
  //     // nftStakingManager.mintRewards(lastEpoch, stakeID2);

  //     vm.prank(validator);
  //     uint256 claimableRewards1 = nftStakingManager.getStakeRewardsForEpoch(stakeID1, lastEpoch);
  //     vm.prank(validator2);
  //     uint256 claimableRewards2 = nftStakingManager.getStakeRewardsForEpoch(stakeID2, lastEpoch);

  //     assertEq(claimableRewards1, epochRewards / 2);
  //     assertEq(claimableRewards2, epochRewards / 2);
  //   }

  //   function test_rewardsSnapshot_alreadySnapped() public {
  //     address validator = getActor("Validator");
  //     uint256 tokenId = 1;
  //     _initiateValidatorRegistration(validator, tokenId);
  //     _completeValidatorRegistration(validator);

  //     // Move to next epoch
  //     vm.warp(block.timestamp + 1 days);

  //     // First snapshot should succeed
  //     nftStakingManager.rewardsSnapshot();

  //     // Second snapshot for the same epoch should fail
  //     vm.expectRevert("Rewards already snapped for this epoch");
  //     nftStakingManager.rewardsSnapshot();

  //     // Move to next epoch
  //     vm.warp(block.timestamp + 1 days);

  //     // Should succeed for new epoch
  //     nftStakingManager.rewardsSnapshot();
  //   }

  //   function test_initiateValidatorRegistration_maxLicenses() public {
  //     address validator = getActor("Validator");

  //     // Mint tokens up to maxLicensesPerValidator + 1
  //     uint256[] memory tokenIds = new uint256[](MAX_LICENSES_PER_VALIDATOR + 1); // max is 10
  //     for (uint256 i = 0; i < tokenIds.length; i++) {
  //       nft.mint(validator, i + 1);
  //       tokenIds[i] = i + 1;
  //     }

  //     vm.startPrank(validator);

  //     // Should revert when trying to stake more than maxLicensesPerValidator
  //     vm.expectRevert("Invalid license count");
  //     nftStakingManager.initiateValidatorRegistration(
  //       DEFAULT_NODE_ID,
  //       DEFAULT_BLS_PUBLIC_KEY,
  //       DEFAULT_P_CHAIN_OWNER,
  //       DEFAULT_P_CHAIN_OWNER,
  //       tokenIds
  //     );

  //     // Should also revert when trying to stake 0 tokens
  //     uint256[] memory emptyTokenIds = new uint256[](0);
  //     vm.expectRevert("Invalid license count");
  //     nftStakingManager.initiateValidatorRegistration(
  //       DEFAULT_NODE_ID,
  //       DEFAULT_BLS_PUBLIC_KEY,
  //       DEFAULT_P_CHAIN_OWNER,
  //       DEFAULT_P_CHAIN_OWNER,
  //       emptyTokenIds
  //     );

  //     // Should succeed with exactly maxLicensesPerValidator
  //     uint256[] memory validTokenIds = new uint256[](10);
  //     for (uint256 i = 0; i < 10; i++) {
  //       validTokenIds[i] = i + 1;
  //     }
  //     bytes32 stakeID = nftStakingManager.initiateValidatorRegistration(
  //       DEFAULT_NODE_ID,
  //       DEFAULT_BLS_PUBLIC_KEY,
  //       DEFAULT_P_CHAIN_OWNER,
  //       DEFAULT_P_CHAIN_OWNER,
  //       validTokenIds
  //     );

  //     assertEq(validatorManager.created(stakeID), true);
  //     vm.stopPrank();
  //   }

  //   function test_completeValidatorRemoval() public {
  //     address validator = getActor("Validator");
  //     uint256 tokenId = 1;
  //     bytes32 stakeID = _initiateValidatorRegistration(validator, tokenId);
  //     _completeValidatorRegistration(validator);

  //     // Verify initial state
  //     assertEq(nftStakingManager.getCurrentTotalStakedLicenses(), 1);
  //     assertEq(nftStakingManager.getTokenLockedBy(tokenId), stakeID);
  //     assertEq(validatorManager.validating(stakeID), true);

  //     // Initiate removal
  //     vm.prank(validator);
  //     nftStakingManager.initiateValidatorRemoval(stakeID);

  //     assertEq(validatorManager.pendingRemoval(stakeID), true, "Validator should be pending removal");

  //     // Complete removal
  //     vm.prank(validator);
  //     bytes32 removedStakeID = nftStakingManager.completeValidatorRemoval(0);

  //     // Verify final state
  //     assertEq(removedStakeID, stakeID, "Returned stake ID should match");
  //     assertEq(
  //       nftStakingManager.getCurrentTotalStakedLicenses(), 0, "Total staked licenses should be 0"
  //     );
  //     assertEq(nftStakingManager.getTokenLockedBy(tokenId), bytes32(0), "Token should be unlocked");
  //     assertEq(validatorManager.validating(stakeID), false, "Validator should not be validating");

  //     // Verify token is still owned by validator
  //     assertEq(nft.ownerOf(tokenId), validator, "Validator should still own the token");
  //   }

  //   function _initiateValidatorRegistration(address validator, uint256 tokenId)
  //     internal
  //     returns (bytes32)
  //   {
  //     nft.mint(validator, tokenId);
  //     uint256[] memory tokenIds = new uint256[](1);
  //     tokenIds[0] = tokenId;

  //     vm.startPrank(validator);
  //     bytes32 stakeID = nftStakingManager.initiateValidatorRegistration(
  //       DEFAULT_NODE_ID,
  //       DEFAULT_BLS_PUBLIC_KEY,
  //       DEFAULT_P_CHAIN_OWNER,
  //       DEFAULT_P_CHAIN_OWNER,
  //       tokenIds
  //     );
  //     vm.stopPrank();
  //     return stakeID;
  //   }

  //   function _completeValidatorRegistration(address validator) internal {
  //     vm.startPrank(validator);
  //     nftStakingManager.completeValidatorRegistration(0);
  //     vm.stopPrank();
  //   }
}
