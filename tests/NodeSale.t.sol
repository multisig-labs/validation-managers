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
  uint256 public MAX_TOKENS = 10000;

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

    // Create array to hold all token IDs
    uint256[] memory tokenIds = new uint256[](MAX_TOKENS);

    // Mint 10000 NFTs and store their IDs
    for (uint256 i = 1; i <= MAX_TOKENS; i++) {
      nft.mint(address(nodeSale), i);
      tokenIds[i - 1] = i; // array is 0-based, so i-1
    }

    // Make all NFTs available for sale
    uint256 gas = gasleft();
    nodeSale.updateAvailableTokenIds(tokenIds);
    gas = gas - gasleft();
    console.log("Gas used:", gas);

    vm.stopPrank();

    vm.prank(manager);
    nodeSale.unpause();
  }

  // function test1() public {
  //   address buyer = getActor("Buyer");
  //   vm.deal(buyer, 10 ether);
  //   vm.prank(buyer);
  //   nodeSale.buyNFT{value: 1 ether}(new bytes32[](0));
  //   string memory storageJson = nodeSale.getStorageAsJson();
  //   console.log(storageJson);
  // }

  function testMassNFTPurchase() public {
    // Create multiple buyers and have them purchase
    for (uint256 i = 1; i <= MAX_TOKENS; i++) {
      address buyer = address(uint160(i));
      vm.deal(buyer, 1 ether); // Give each buyer 1 ETH

      vm.startPrank(buyer);
      nodeSale.buyNFT{value: 1 ether}(new bytes32[](0)); // Assuming no whitelist
      vm.stopPrank();
    }

    assertEq(nodeSale.totalSold(), MAX_TOKENS);
    assertEq(nodeSale.getRemainingSupply(), 0);
  }
}
