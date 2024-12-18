// SPDX-License-Identifier: Ecosystem

pragma solidity 0.8.25;

import {BaseTest} from "./BaseTest.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MockValidatorManager} from "../contracts/mocks/MockValidatorManager.sol";
import {ValidatorRegistrationInput, PChainOwner} from "../contracts/interfaces/IValidatorManager.sol";
import {IStakingManager, StakingInput} from "../contracts/interfaces/IStakingManager.sol";
import {StakingManager} from "../contracts/StakingManager.sol";

contract StakingManagerTests is BaseTest {
  address admin;
  MockValidatorManager validatorManager;
  StakingManager stakingManager;
  
  function setUp() public {
    admin = makeActor("Joe");

    validatorManager = new MockValidatorManager();

    StakingManager stakingManagerImplementation = new StakingManager();
    bytes memory initData = abi.encodeWithSelector(StakingManager.initialize.selector, validatorManager);
    ERC1967Proxy proxy = new ERC1967Proxy(address(stakingManagerImplementation), initData);
    stakingManager = StakingManager(address(proxy));
  }

  function test_StakeToken() public {
    vm.deal(admin, 100);
    PChainOwner memory pChainOwner = makePChainOwner(admin);

    StakingInput memory stakingInput = StakingInput({
      owner: admin, 
      tokenAddress: address(0),
      amount: 101, 
      nftAddress: address(0),
      nftId: 0,
      minimumStakeDuration: 1000,
      input: ValidatorRegistrationInput({
        nodeID: DEFAULT_INITIAL_VALIDATOR_NODE_ID_1,
        blsPublicKey: DEFAULT_BLS_PUBLIC_KEY,
        registrationExpiry: uint64(block.timestamp) + 100,
        remainingBalanceOwner: pChainOwner,
        disableOwner: pChainOwner
      })
    });
    stakingManager.initializeStake{value: 101}(stakingInput);
    stakingManager.completeStake(0);
  }

  //   function test_ICTTStaking() public {
  //   vm.deal(admin, 100);
  //   PChainOwner memory pChainOwner = makePChainOwner(admin);

  //   StakingInput memory stakingInput = StakingInput({
  //     staker: admin, 
  //     amount: 100, 
  //     input: ValidatorRegistrationInput({
  //       nodeID: DEFAULT_INITIAL_VALIDATOR_NODE_ID_1,
  //       blsPublicKey: DEFAULT_BLS_PUBLIC_KEY,
  //       registrationExpiry: uint64(block.timestamp) + 100,
  //       remainingBalanceOwner: pChainOwner,
  //       disableOwner: pChainOwner
  //     })
  //   });

  //   bytes memory payload = abi.encode(stakingInput);
  //   stakingManager.receiveTokens{value: 100}(bytes32(0), admin, admin, payload);
  // }


}

