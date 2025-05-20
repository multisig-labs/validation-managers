// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

import { Base } from "./utils/Base.sol";

import { NFTStakingManagerSettings } from "../contracts/NFTStakingManager.sol";
import { NFTStakingManagerGasless } from "../contracts/NFTStakingManagerGasless.sol";
import { NodeLicense, NodeLicenseSettings } from "../contracts/tokens/NodeLicense.sol";
import { ERC2771ForwarderUseful } from "../contracts/utils/ERC2771ForwarderUseful.sol";
import { ERC2771Forwarder } from "@openzeppelin-contracts-5.3.0/metatx/ERC2771Forwarder.sol";

import {
  PChainOwner,
  Validator,
  ValidatorStatus
} from "icm-contracts-2.0.0/contracts/validator-manager/interfaces/IACP99Manager.sol";

import { ERC721Mock } from "./mocks/ERC721Mock.sol";
import { NativeMinterMock } from "./mocks/NativeMinterMock.sol";
import { MockValidatorManager } from "./mocks/ValidatorManagerMock.sol";

import { ERC1967Proxy } from "@openzeppelin-contracts-5.3.0/proxy/ERC1967/ERC1967Proxy.sol";

contract NFTStakingManagerGaslessTest is Base {
  NodeLicense public nft;
  ERC721Mock public hardwareNft;
  MockValidatorManager public validatorManager;
  NFTStakingManagerGasless public nftStakingManager;
  ERC2771ForwarderUseful public forwarder;

  address public admin;

  uint256 public epochRewards = 1000 ether;
  uint16 public MAX_LICENSES_PER_VALIDATOR = 40;
  uint64 public LICENSE_WEIGHT = 1000;
  uint64 public HARDWARE_LICENSE_WEIGHT = 0;
  uint32 public GRACE_PERIOD = 1 hours;
  uint32 public DELEGATION_FEE_BIPS = 1000;
  address public constant WARP_PRECOMPILE_ADDRESS = 0x0200000000000000000000000000000000000005;
  uint32 public EPOCH_DURATION = 1 days;
  uint256 public BIPS_CONVERSION_FACTOR = 10000;

  bytes32 public constant DEFAULT_SOURCE_BLOCKCHAIN_ID =
    bytes32(hex"abcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcd");

  function setUp() public override {
    super.setUp();
    admin = getActor("Admin");

    validatorManager = new MockValidatorManager();

    hardwareNft = new ERC721Mock("Hardware NFT License", "HARDNFTL");

    NodeLicense nodeLicenseImpl = new NodeLicense();
    ERC1967Proxy nodeLicenseProxy = new ERC1967Proxy(
      address(nodeLicenseImpl),
      abi.encodeCall(
        NodeLicense.initialize,
        NodeLicenseSettings({
          name: "NFT License",
          symbol: "NFTL",
          admin: admin,
          minter: address(this),
          nftStakingManager: address(nftStakingManager),
          baseTokenURI: "https://example.com/nft/",
          unlockTime: 0
        })
      )
    );
    nft = NodeLicense(address(nodeLicenseProxy));

    forwarder = new ERC2771ForwarderUseful("forwarder");

    NFTStakingManagerGasless stakingManagerImpl = new NFTStakingManagerGasless();
    ERC1967Proxy stakingManagerProxy = new ERC1967Proxy(
      address(stakingManagerImpl),
      abi.encodeCall(
        NFTStakingManagerGasless.initialize,
        (
          _defaultNFTStakingManagerSettings(
            address(validatorManager), address(nft), address(hardwareNft)
          ),
          address(forwarder)
        )
      )
    );
    nftStakingManager = NFTStakingManagerGasless(address(stakingManagerProxy));

    vm.prank(admin);
    nft.setNFTStakingManager(address(nftStakingManager));

    NativeMinterMock nativeMinter = new NativeMinterMock();
    vm.etch(0x0200000000000000000000000000000000000001, address(nativeMinter).code);
  }

  function _defaultNFTStakingManagerSettings(
    address validatorManager_,
    address license_,
    address hardwareLicense_
  ) internal view returns (NFTStakingManagerSettings memory) {
    return NFTStakingManagerSettings({
      admin: admin,
      validatorManager: validatorManager_,
      license: license_,
      hardwareLicense: hardwareLicense_,
      initialEpochTimestamp: uint32(block.timestamp),
      epochDuration: EPOCH_DURATION,
      licenseWeight: LICENSE_WEIGHT,
      hardwareLicenseWeight: HARDWARE_LICENSE_WEIGHT,
      epochRewards: epochRewards,
      maxLicensesPerValidator: MAX_LICENSES_PER_VALIDATOR,
      gracePeriod: GRACE_PERIOD,
      uptimePercentageBips: 8000,
      bypassUptimeCheck: false,
      minDelegationEpochs: 0
    });
  }

  function test_TrustedForwarder() public {
    assertEq(nftStakingManager.trustedForwarder(), address(forwarder));
    nftStakingManager.setTrustedForwarder(address(0));
    assertEq(nftStakingManager.trustedForwarder(), address(0));
  }

  function test_gasless() public {
    uint256 alicePK = 0xa11ce;
    address alice = vm.addr(alicePK);
    vm.deal(alice, 1 ether);

    uint256 hardwareTokenId = hardwareNft.mint(alice);

    bytes memory data = abi.encodeWithSelector(
      nftStakingManager.initiateValidatorRegistration.selector,
      DEFAULT_NODE_ID,
      DEFAULT_BLS_PUBLIC_KEY,
      DEFAULT_BLS_POP,
      DEFAULT_P_CHAIN_OWNER,
      DEFAULT_P_CHAIN_OWNER,
      hardwareTokenId,
      DELEGATION_FEE_BIPS
    );

    // Create and sign the forward request
    ERC2771Forwarder.ForwardRequestData memory requestData = ERC2771Forwarder.ForwardRequestData({
      from: alice,
      to: address(nftStakingManager),
      value: 0,
      gas: 3000000,
      deadline: uint48(block.timestamp + 1 days),
      data: data,
      signature: bytes("")
    });

    bytes32 digest = forwarder.structHash(requestData);
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePK, digest);
    requestData.signature = abi.encodePacked(r, s, v);

    // Execute the forward request
    forwarder.execute(requestData);

    assertEq(nftStakingManager.getValidationIDs().length, 1);
  }
}
