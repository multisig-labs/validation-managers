// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

import { NFTStakingManager, ValidationInfoView } from "../../contracts/NFTStakingManager.sol";
import { NFTStakingManagerBase } from "../utils/NFTStakingManagerBase.sol";
import {
  Validator,
  ValidatorStatus
} from "icm-contracts-2.0.0/contracts/validator-manager/interfaces/IACP99Manager.sol";

contract NFTStakingManagerValidatorRemovalTest is NFTStakingManagerBase {
  //
  // VALIDATOR REMOVAL
  //
  function test_initiateValidatorRemoval() public {
    (bytes32 validationID, address validator) = _createValidator();
    (bytes32 delegationID,) = _createDelegation(validationID, 1);

    address otherAddress = getActor("OtherAddress");
    vm.startPrank(otherAddress);
    vm.expectRevert(NFTStakingManager.UnauthorizedOwner.selector);
    nftStakingManager.initiateValidatorRemoval(validationID);
    vm.stopPrank();

    uint32 currentEpoch = nftStakingManager.getEpochByTimestamp(block.timestamp);

    bytes32[] memory delegationIDs = new bytes32[](1);
    delegationIDs[0] = delegationID;

    vm.startPrank(validator);
    vm.expectRevert(NFTStakingManager.ValidatorHasActiveDelegations.selector);
    nftStakingManager.initiateValidatorRemoval(validationID);

    nftStakingManager.initiateDelegatorRemoval(delegationIDs);
    nftStakingManager.initiateValidatorRemoval(validationID);

    ValidationInfoView memory validationInfo = nftStakingManager.getValidationInfoView(validationID);
    assertEq(validationInfo.endEpoch, currentEpoch);

    Validator memory v = validatorManager.getValidator(validationID);

    assertEq(uint8(v.status), uint8(ValidatorStatus.PendingRemoved));
  }

  function test_completeValidatorRemoval() public {
    // Create validator and initiate removal
    address validator = getActor("Validator");
    uint256 hardwareTokenId = hardwareNft.mint(validator);

    (bytes32 validationID,) = _createValidator(validator, hardwareTokenId);
    (bytes32 delegationID,) = _createDelegation(validationID, 1);

    vm.startPrank(validator);
    vm.expectRevert(NFTStakingManager.ValidatorHasActiveDelegations.selector);
    nftStakingManager.initiateValidatorRemoval(validationID);
    vm.stopPrank();

    bytes32[] memory delegationIDs = new bytes32[](1);
    delegationIDs[0] = delegationID;

    vm.prank(validator);
    nftStakingManager.initiateDelegatorRemoval(delegationIDs);

    vm.prank(validator);
    nftStakingManager.initiateValidatorRemoval(validationID);

    // Complete the removal
    bytes32 returnedValidationID = nftStakingManager.completeValidatorRemoval(0);
    assertEq(returnedValidationID, validationID);

    // Verify hardware token is unlocked
    assertEq(nftStakingManager.getHardwareTokenLockedBy(hardwareTokenId), bytes32(0));

    Validator memory v = validatorManager.getValidator(validationID);

    // Verify validator manager state
    assertEq(uint8(v.status), uint8(ValidatorStatus.Completed));
  }

  function test_initiateValidatorRemoval_unauthorizedOwner() public {
    (bytes32 validationID,) = _createValidator();

    address unauthorized = getActor("Unauthorized");
    vm.startPrank(unauthorized);
    vm.expectRevert(NFTStakingManager.UnauthorizedOwner.selector);
    nftStakingManager.initiateValidatorRemoval(validationID);
    vm.stopPrank();
  }

  function test_initiateValidatorRemoval_withActiveDelegations() public {
    (bytes32 validationID, address validator) = _createValidator();
    _createDelegation(validationID, 1);

    vm.startPrank(validator);
    vm.expectRevert(NFTStakingManager.ValidatorHasActiveDelegations.selector);
    nftStakingManager.initiateValidatorRemoval(validationID);
    vm.stopPrank();
  }

  function test_initiateValidatorRemoval_withoutDelegations() public {
    (bytes32 validationID, address validator) = _createValidator();
    uint32 currentEpoch = nftStakingManager.getEpochByTimestamp(block.timestamp);

    vm.startPrank(validator);
    nftStakingManager.initiateValidatorRemoval(validationID);
    vm.stopPrank();

    ValidationInfoView memory validationInfo = nftStakingManager.getValidationInfoView(validationID);
    assertEq(validationInfo.endEpoch, currentEpoch);

    Validator memory v = validatorManager.getValidator(validationID);
    assertEq(uint8(v.status), uint8(ValidatorStatus.PendingRemoved));
  }
}
