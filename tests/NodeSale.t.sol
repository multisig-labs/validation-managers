// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

import {ERC721Mock} from "../contracts/mocks/ERC721Mock.sol";
import {ERC1967Proxy} from "@openzeppelin-contracts-5.2.0/proxy/ERC1967/ERC1967Proxy.sol";

import {NodeSaleWithWhitelist} from "../contracts/node-sale/NodeSaleWithWhitelist.sol";
import {Base} from "./utils/Base.sol";
import {console} from "forge-std-1.9.6/src/console.sol";

contract NodeSaleTest is Base {
  ERC721Mock public nft;
  NodeSaleWithWhitelist public nodeSale;
  address public admin;
  address public manager;
  address public treasury;
  uint256 public BATCHES = 10;
  uint256 public MAX_TOKENS_PER_BATCH = 1000;

  function setUp() public override {
    super.setUp();
    admin = getActor("Admin");
    manager = getActor("Manager");
    treasury = getActor("Treasury");
    nft = new ERC721Mock("Test NFT", "TEST");

    vm.startPrank(admin);

    // Deploy implementation
    NodeSaleWithWhitelist implementation = new NodeSaleWithWhitelist();

    // Encode initialization data
    bytes memory initData = abi.encodeWithSelector(
      NodeSaleWithWhitelist.initialize.selector,
      address(nft), // _nftContract
      1 ether, // _price
      10, // _maxPerWallet
      admin, // _initialAdmin
      treasury // _treasury
    );

    // Deploy proxy
    ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);

    // Cast proxy to NodeSaleWithWhitelist
    nodeSale = NodeSaleWithWhitelist(address(proxy));
    nodeSale.grantRole(nodeSale.MANAGER_ROLE(), manager);

    // Mint NFTs
    for (uint256 i = 1; i <= BATCHES * MAX_TOKENS_PER_BATCH; i++) {
      nft.mint(address(nodeSale), i);
    }

    vm.stopPrank();

    vm.startPrank(manager);
    // Make all NFTs available for sale
    for (uint256 i = 0; i < BATCHES; i++) {
      uint256 startIndex = 1 + i * MAX_TOKENS_PER_BATCH;
      uint256[] memory batchTokenIds = new uint256[](MAX_TOKENS_PER_BATCH);
      for (uint256 j = startIndex; j < startIndex + MAX_TOKENS_PER_BATCH; j++) {
        batchTokenIds[j - startIndex] = j;
      }
      uint256 gas = gasleft();
      nodeSale.appendAvailableTokenIds(batchTokenIds);
      calculateGasCostInUSD("Appending batch:", gas - gasleft());
    }
    nodeSale.unpause();
    vm.stopPrank();
  }

  function testMassNFTPurchase() public {
    // Create multiple buyers and have them purchase
    for (uint256 i = 1; i <= (BATCHES * MAX_TOKENS_PER_BATCH) / 10; i++) {
      address buyer = address(uint160(i));
      vm.deal(buyer, 10 ether);

      vm.startPrank(buyer);
      nodeSale.buyNFTs{value: 10 ether}(10, new bytes32[](0)); // Assuming no whitelist
      assertEq(buyer.balance, 0);
      vm.stopPrank();
    }

    assertEq(nodeSale.totalSold(), BATCHES * MAX_TOKENS_PER_BATCH);
    assertEq(nodeSale.getRemainingSupply(), 0);
    assertEq(nft.balanceOf(address(nodeSale)), 0);
    assertEq(address(nodeSale).balance, BATCHES * MAX_TOKENS_PER_BATCH * 1 ether);

    vm.prank(manager);
    nodeSale.withdraw();

    assertEq(address(nodeSale).balance, 0);
    assertEq(treasury.balance, BATCHES * MAX_TOKENS_PER_BATCH * 1 ether);
  }

  function logArrayInline(uint256[] memory arr) internal pure {
    string memory output = "[";
    for (uint256 i = 0; i < arr.length; i++) {
      if (i > 0) {
        output = string.concat(output, ", ");
      }
      output = string.concat(output, vm.toString(arr[i]));
    }
    output = string.concat(output, "]");
    console.log(output);
  }

  function calculateGasCostInUSD(string memory action, uint256 gasUsed) internal pure {
    uint256 gasPrice = 2 * 1e9; // 2 nAVAX
    uint256 avaxPrice = 20_00; // $20.00 (stored as 2000 cents)

    // Calculate total cost in wei
    uint256 gasCostInWei = gasUsed * gasPrice;

    // Calculate USD cost in cents (multiply by price in cents)
    uint256 gasCostInCents = (gasCostInWei * avaxPrice) / 1e18;

    // Split into dollars and cents
    uint256 dollars = gasCostInCents / 100;
    uint256 cents = gasCostInCents % 100;

    // Format with proper decimal places
    string memory centsStr = cents < 10 ? string.concat("0", vm.toString(cents)) : vm.toString(cents);

    console.log(string.concat(action, " Gas Cost: $", vm.toString(dollars), ".", centsStr));
  }
}
