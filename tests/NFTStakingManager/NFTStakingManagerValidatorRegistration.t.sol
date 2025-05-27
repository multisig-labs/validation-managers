// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

import { NFTStakingManager, ValidationInfoView } from "../../contracts/NFTStakingManager.sol";
import { NFTStakingManagerBase } from "../utils/NFTStakingManagerBase.sol";
import {
  Validator,
  ValidatorStatus
} from "icm-contracts-2.0.0/contracts/validator-manager/interfaces/IACP99Manager.sol";

contract NFTStakingManagerValidatorRegistrationTest is NFTStakingManagerBase {
  //
  // VALIDATOR REGISTRATION
  //
  function test_initiateValidatorRegistration() public {
    address validator = getActor("Validator");
    uint256 hardwareTokenId = hardwareNft.mint(validator);
    uint32 currentEpoch = nftStakingManager.getEpochByTimestamp(block.timestamp);

    vm.startPrank(validator);
    bytes32 validationID = nftStakingManager.initiateValidatorRegistration(
      DEFAULT_NODE_ID,
      DEFAULT_BLS_PUBLIC_KEY,
      DEFAULT_BLS_POP,
      DEFAULT_P_CHAIN_OWNER,
      DEFAULT_P_CHAIN_OWNER,
      hardwareTokenId,
      DELEGATION_FEE_BIPS
    );
    vm.stopPrank();

    Validator memory v = validatorManager.getValidator(validationID);

    assertEq(hardwareNft.balanceOf(validator), 1);
    assertEq(uint8(v.status), uint8(ValidatorStatus.PendingAdded));
    assertEq(v.weight, HARDWARE_LICENSE_WEIGHT);

    assertEq(nftStakingManager.getValidationIDs().length, 1);
    assertEq(nftStakingManager.getValidationIDs()[0], validationID);

    ValidationInfoView memory validationInfoView =
      nftStakingManager.getValidationInfoView(validationID);
    assertEq(validationInfoView.startEpoch, 0);
    assertEq(validationInfoView.delegationFeeBips, DELEGATION_FEE_BIPS);
    assertEq(validationInfoView.owner, validator);
    assertEq(validationInfoView.hardwareTokenID, hardwareTokenId);

    nftStakingManager.completeValidatorRegistration(0);

    v = validatorManager.getValidator(validationID);
    validationInfoView = nftStakingManager.getValidationInfoView(validationID);
    assertEq(uint8(v.status), uint8(ValidatorStatus.Active));
    assertEq(validationInfoView.startEpoch, currentEpoch);
  }

  function test_initiateValidatorRegistration_invalidDelegationFee() public {
    address validator = getActor("Validator");
    uint256 hardwareTokenId = hardwareNft.mint(validator);

    vm.startPrank(validator);

    // Test delegation fee too high (> 100%)
    vm.expectRevert(
      abi.encodeWithSelector(NFTStakingManager.InvalidDelegationFeeBips.selector, 10001)
    );
    nftStakingManager.initiateValidatorRegistration(
      DEFAULT_NODE_ID,
      DEFAULT_BLS_PUBLIC_KEY,
      DEFAULT_BLS_POP,
      DEFAULT_P_CHAIN_OWNER,
      DEFAULT_P_CHAIN_OWNER,
      hardwareTokenId,
      10001 // > 10000 (100%)
    );

    vm.stopPrank();
  }

  function test_initiateValidatorRegistration_unauthorizedOwner() public {
    address validator = getActor("Validator");
    address unauthorized = getActor("Unauthorized");
    uint256 hardwareTokenId = hardwareNft.mint(validator);

    vm.startPrank(unauthorized);
    vm.expectRevert(NFTStakingManager.UnauthorizedOwner.selector);
    nftStakingManager.initiateValidatorRegistration(
      DEFAULT_NODE_ID,
      DEFAULT_BLS_PUBLIC_KEY,
      DEFAULT_BLS_POP,
      DEFAULT_P_CHAIN_OWNER,
      DEFAULT_P_CHAIN_OWNER,
      hardwareTokenId,
      DELEGATION_FEE_BIPS
    );
    vm.stopPrank();
  }

  function test_completeValidatorRegistration() public {
    address validator = getActor("Validator");
    uint256 hardwareTokenId = hardwareNft.mint(validator);
    uint32 currentEpoch = nftStakingManager.getEpochByTimestamp(block.timestamp);

    vm.startPrank(validator);
    bytes32 validationID = nftStakingManager.initiateValidatorRegistration(
      DEFAULT_NODE_ID,
      DEFAULT_BLS_PUBLIC_KEY,
      DEFAULT_BLS_POP,
      DEFAULT_P_CHAIN_OWNER,
      DEFAULT_P_CHAIN_OWNER,
      hardwareTokenId,
      DELEGATION_FEE_BIPS
    );
    vm.stopPrank();

    // Verify initial state
    Validator memory v = validatorManager.getValidator(validationID);
    assertEq(uint8(v.status), uint8(ValidatorStatus.PendingAdded));

    ValidationInfoView memory validationInfoView =
      nftStakingManager.getValidationInfoView(validationID);
    assertEq(validationInfoView.startEpoch, 0);

    // Complete registration
    bytes32 returnedValidationID = nftStakingManager.completeValidatorRegistration(0);
    assertEq(returnedValidationID, validationID);

    // Verify final state
    v = validatorManager.getValidator(validationID);
    assertEq(uint8(v.status), uint8(ValidatorStatus.Active));

    validationInfoView = nftStakingManager.getValidationInfoView(validationID);
    assertEq(validationInfoView.startEpoch, currentEpoch);
  }
}
