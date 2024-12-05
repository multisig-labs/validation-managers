// SPDX-License-Identifier: Ecosystem

pragma solidity 0.8.25;

import {BaseTest} from "./BaseTest.sol";

import {NFTStakingManager} from "../contracts/validator-manager/NFTStakingManager.sol";
import {ICMInitializable} from "@avalabs/teleporter-contracts/utilities/ICMInitializable.sol";
import {ExampleRewardCalculator} from "@avalabs/teleporter-contracts/validator-manager/ExampleRewardCalculator.sol";
import {ValidatorMessages} from "@avalabs/teleporter-contracts/validator-manager/ValidatorMessages.sol";
import {PoSValidatorManagerSettings} from "@avalabs/teleporter-contracts/validator-manager/interfaces/IPoSValidatorManager.sol";
import {IRewardCalculator} from "@avalabs/teleporter-contracts/validator-manager/interfaces/IRewardCalculator.sol";
import {
  ConversionData,
  IValidatorManager,
  InitialValidator,
  PChainOwner,
  Validator,
  ValidatorManagerSettings,
  ValidatorRegistrationInput,
  ValidatorStatus
} from "@avalabs/teleporter-contracts/validator-manager/interfaces/IValidatorManager.sol";
import {IERC721Errors} from "@openzeppelin/contracts@5.0.2/interfaces/draft-IERC6093.sol";
import {ExampleERC721} from "@mocks/ExampleERC721.sol";
import {MockNativeMinter} from "@mocks/MockNativeMinter.sol";
import {MockWarpMessenger, WarpMessage} from "@mocks/MockWarpMessenger.sol";
import {NFTLicenseModule} from "../contracts/validator-manager/NFTLicenseModule.sol";
import {ValidatorReceipt} from "../contracts/tokens/ValidatorReceipt.sol";
import {Certificates} from "../contracts/tokens/Certificates.sol";
import {NFTValidatorManagerSettings} from "../contracts/interfaces/INFTStakingManager.sol";

contract BlackBoxNFTTests is BaseTest {
  uint8 public constant DEFAULT_MAXIMUM_CHURN_PERCENTAGE = 20;
  uint64 public constant DEFAULT_CHURN_PERIOD = 1 hours;

  NFTStakingManager public app;
  ExampleERC721 public nft;
  ExampleERC721 public receiptNft;
  Certificates public certificates;
  NFTLicenseModule public licenseModule;
  IRewardCalculator public rewardCalculator;
  MockWarpMessenger public warp;
  MockNativeMinter public nativeMinter;
  address public owner;

  receive() external payable {}
  fallback() external payable {}

  function setUp() public {
    owner = makeActor("initialOwner");

    warp = makeWarpMock();
    nativeMinter = makeNativeMinterMock();
    nft = new ExampleERC721();
    receiptNft = new ExampleERC721();

    certificates = new Certificates();
    certificates.initialize(address(this), address(this), address(this), "https://example.com/");

    licenseModule = new NFTLicenseModule();
    licenseModule.initialize(address(this));
    licenseModule.setCertificateNFTAddress(address(certificates));
    licenseModule.setAllowedNFT(address(nft), uint64(1000));

    app = new NFTStakingManager(ICMInitializable.Allowed);

    app.initialize(
      NFTValidatorManagerSettings({
        baseSettings: ValidatorManagerSettings({
          subnetID: DEFAULT_SUBNET_ID,
          churnPeriodSeconds: DEFAULT_CHURN_PERIOD,
          maximumChurnPercentage: DEFAULT_MAXIMUM_CHURN_PERCENTAGE
        }),
        rewardCalculator: rewardCalculator,
        licenseModule: licenseModule,
        validatorReceiptAddress: address(receiptNft),
        uptimeBlockchainID: DEFAULT_UPTIME_BLOCKCHAIN_ID
      }),
      owner
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

  function testStakeNFT() public {
    address nodeOwner = makeActor("nodeOwner");
    certificates.mint(nodeOwner, keccak256("KYC"));
    uint256 nftId = nft.mint(nodeOwner);
    PChainOwner memory pChainOwner = makePChainOwner(nodeOwner);
    uint64 registrationExpiry = uint64(block.timestamp) + 100;

    bytes memory nodeID = randNodeID();

    vm.startPrank(nodeOwner);

    nft.approve(address(app), nftId);
    bytes32 validationID = app.initializeValidatorRegistration(
      ValidatorRegistrationInput({
        nodeID: nodeID,
        blsPublicKey: DEFAULT_BLS_PUBLIC_KEY,
        registrationExpiry: registrationExpiry,
        remainingBalanceOwner: pChainOwner,
        disableOwner: pChainOwner
      }),
      address(nft),
      1
    );

    // Check that nft is now owned by the app
    assertEq(nft.ownerOf(nftId), address(app));
    // Check that receiptNft is now owned by the nodeOwner
    uint256 receiptId = app.getValidatorInfo(validationID).receiptId;
    assertEq(receiptNft.ownerOf(receiptId), nodeOwner);

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
    assertEq(app.getValidatorInfo(validationID).uptimeSeconds, uint64(block.timestamp) - validator.startedAt);

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

    // nodeOwner should have their NFT back
    assertEq(nft.ownerOf(nftId), nodeOwner);

    // receipt NFT should be burned
    vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, receiptId));
    receiptNft.ownerOf(receiptId);

    // Check for native token rewards
    assertGt(address(this).balance, 0);
  }
}
