// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

import { Test } from "forge-std-1.9.6/src/Test.sol";
import { PChainOwner } from "icm-contracts-d426c55/contracts/validator-manager/ACP99Manager.sol";

abstract contract Base is Test {
  PChainOwner public DEFAULT_P_CHAIN_OWNER;
  bytes public constant DEFAULT_BLS_PUBLIC_KEY = bytes(
    hex"8d543b279b9bd69c5b6754a09bce1eab2de2d9135eff7e391e42583fca4c19c6007e864971c2baba777dfa312ca7994e"
  );
  bytes public constant DEFAULT_BLS_POP = bytes(
    hex"a99743e050b543f2482c1010e2908b848c5894080a5e5ac9db96111b721d753efbe106eb12496b56be14f11feaeb4d9605507ca0cb726b3832c45448603025de7ba425d7c054f5e664922d6a5dfab8b9f7df681941d25be420ea4f973b79d041"
  );
  bytes public constant DEFAULT_NODE_ID = bytes(hex"1234123412341234123412341234123412341234");

  uint256 private randNonce = 0;
  uint160 private actorCounter = 0;

  function getActor(string memory name) public returns (address) {
    actorCounter++;
    address addr = address(uint160(0x10000 + actorCounter));
    vm.label(addr, name);
    return addr;
  }

  // The same name will always return the same address
  function getNamedActor(string memory name) public returns (address) {
    bytes32 hash = keccak256(abi.encodePacked(name));
    address addr = address(uint160(uint256(hash)));
    vm.label(addr, name);
    return addr;
  }

  function setUp() public virtual {
    address[] memory addresses = new address[](1);
    addresses[0] = 0x1234567812345678123456781234567812345678;
    DEFAULT_P_CHAIN_OWNER = PChainOwner({ threshold: 1, addresses: addresses });
  }

  // Copy over some funcs from DSTestPlus
  string private checkpointLabel;
  uint256 private checkpointGasLeft;

  function startMeasuringGas(string memory label) internal virtual {
    checkpointLabel = label;
    checkpointGasLeft = gasleft();
  }

  function stopMeasuringGas() internal virtual {
    uint256 checkpointGasLeft2 = gasleft();

    string memory label = checkpointLabel;

    emit log_named_uint(
      string(abi.encodePacked(label, " Gas")), checkpointGasLeft - checkpointGasLeft2
    );
  }
}
