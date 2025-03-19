// SPDX-License-Identifier: Ecosystem

pragma solidity 0.8.25;

import {MockWarpMessenger, WarpMessage} from "../contracts/mocks/MockWarpMessenger.sol";
import {BaseTest} from "./BaseTest.sol";

contract WarpMockTests is BaseTest {
  MockWarpMessenger public warp;

  function setUp() public {
    warp = makeWarpMock();
  }

  function testWarpMock() public {
    bytes memory payloadBytes_1 = abi.encode("payload_1");
    bytes32 messageID_1 = warp.sendWarpMessage(payloadBytes_1);

    bytes memory payloadBytes_2 = abi.encode("payload_2");
    bytes32 messageID_2 = warp.sendWarpMessage(payloadBytes_2);

    // Get directly from storage
    (bytes32 sourceChainID, address sender, bytes memory payload) = warp.messages(messageID_1);
    assertEq(sourceChainID, warp.getBlockchainID());
    assertEq(sender, address(this));
    assertEq(payload, payloadBytes_1);

    // Get from getVerifiedWarpMessage
    (WarpMessage memory message, bool valid) = warp.getVerifiedWarpMessage(0);
    assertEq(valid, true);
    assertEq(message.sourceChainID, warp.getBlockchainID());
    assertEq(message.originSenderAddress, address(this));
    assertEq(message.payload, payloadBytes_1);

    // Get directly from storage
    (sourceChainID, sender, payload) = warp.messages(messageID_2);
    assertEq(sourceChainID, warp.getBlockchainID());
    assertEq(sender, address(this));
    assertEq(payload, payloadBytes_2);

    (message, valid) = warp.getVerifiedWarpMessage(1);
    assertEq(valid, true);
    assertEq(message.sourceChainID, warp.getBlockchainID());
    assertEq(message.originSenderAddress, address(this));
    assertEq(message.payload, payloadBytes_2);

    (message, valid) = warp.getVerifiedWarpMessage(2);
    assertEq(valid, false);
  }
}
