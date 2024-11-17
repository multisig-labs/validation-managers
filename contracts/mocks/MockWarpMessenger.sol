// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

struct WarpMessage {
    bytes32 sourceChainID;
    address originSenderAddress;
    bytes payload;
}

struct WarpBlockHash {
    bytes32 sourceChainID;
    bytes32 blockHash;
}

contract MockWarpMessenger {
    // Store all messages in a mapping
    mapping(bytes32 => WarpMessage) public messages;
    mapping(bytes32 => uint32) public messageIndexes;

    // Add storage for predicate slots for testing
    uint32 private _predicateSlotIndex;
    mapping(uint32 => bytes32) private _predicateSlots;
    bytes32 private _blockchainID;

    event SendWarpMessage(address indexed sender, bytes32 indexed messageID, bytes message);

    function sendWarpMessage(
        bytes calldata payload
    ) external returns (bytes32 messageID) {
        setWarpMessage(msg.sender, this.getBlockchainID(), payload);
        messageID = keccak256(payload);
        emit SendWarpMessage(msg.sender, messageID, payload);
    }

    function getVerifiedWarpMessage(
        uint32 index
    ) external view returns (WarpMessage memory message, bool valid) {
        message = messages[_predicateSlots[index]];
        valid = message.payload.length > 0;
        return (message, valid);
    }

    // TODO mock this out as well
    function getVerifiedWarpBlockHash(
        uint32 /* index */
    ) external view returns (WarpBlockHash memory warpBlockHash, bool valid) {
        warpBlockHash =
            WarpBlockHash({sourceChainID: this.getBlockchainID(), blockHash: bytes32(0)});
        valid = true;
    }

    // getBlockchainID returns the snow.Context BlockchainID of this chain.
    // This blockchainID is the hash of the transaction that created this blockchain on the P-Chain
    // and is not related to the Ethereum ChainID.
    function getBlockchainID() external view returns (bytes32 blockchainID) {
        return _blockchainID == bytes32(0) ? bytes32(keccak256("test_chain")) : _blockchainID;
    }

    // Helper Functions

    // For testing purposes, set the blockchain ID
    function setBlockchainID(
        bytes32 blockchainID
    ) external {
        _blockchainID = blockchainID;
    }

    // Clear out internal data storage
    function reset() external {
        for (uint32 i = 0; i < _predicateSlotIndex; i++) {
            delete messages[_predicateSlots[i]];
            delete messageIndexes[_predicateSlots[i]];
            delete _predicateSlots[i];
        }
        _predicateSlotIndex = 0;
    }

    // Use to mock a warp message from the P chain.
    function setWarpMessageFromP(
        bytes calldata payload
    ) public returns (uint32 index, bytes32 messageID) {
        return setWarpMessage(address(0), bytes32(0), payload);
    }

    // Store a warp message locally to be retrieved later via getVerifiedWarpMessage(index)
    function setWarpMessage(
        address originSenderAddress,
        bytes32 sourceChainID,
        bytes calldata payload
    ) public returns (uint32 index, bytes32 messageID) {
        index = _predicateSlotIndex++;
        messageID = keccak256(payload);
        _predicateSlots[index] = messageID;
        messageIndexes[messageID] = index;
        messages[messageID] = WarpMessage({
            sourceChainID: sourceChainID,
            originSenderAddress: originSenderAddress,
            payload: payload
        });
    }
}
