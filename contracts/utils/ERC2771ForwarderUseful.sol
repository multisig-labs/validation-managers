// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

import { ERC2771Forwarder } from "@openzeppelin-contracts-5.3.0/metatx/ERC2771Forwarder.sol";

// An actually useful version that includes a way to get the struct hash
contract ERC2771ForwarderUseful is ERC2771Forwarder {
  constructor(string memory name) ERC2771Forwarder(name) { }

  function structHash(ForwardRequestData calldata request) external view returns (bytes32) {
    uint256 currentNonce = nonces(request.from);
    bytes32 structHashPayload = keccak256(
      abi.encode(
        _FORWARD_REQUEST_TYPEHASH,
        request.from,
        request.to,
        request.value,
        request.gas,
        currentNonce,
        request.deadline,
        keccak256(request.data)
      )
    );
    return _hashTypedDataV4(structHashPayload);
  }
}
