// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

import {Base} from "./utils/Base.sol";

import {LicenseVault} from "../contracts/LicenseVault.sol";
import {NFTStakingManager, NFTStakingManagerSettings} from "../contracts/NFTStakingManager.sol";
import {ERC721Mock} from "../contracts/mocks/ERC721Mock.sol";
import {ValidatorManagerMock} from "../contracts/mocks/ValidatorManagerMock.sol";
import {IWarpMessenger, WarpMessage} from "./utils/IWarpMessenger.sol";

import {ERC1967Proxy} from "@openzeppelin-contracts-5.2.0/proxy/ERC1967/ERC1967Proxy.sol";
import {console2} from "forge-std-1.9.6/src/console2.sol";
import {PChainOwner} from "icm-contracts-8817f47/contracts/validator-manager/ACP99Manager.sol";

contract LicenseVaultTest is Base {
  ERC721Mock public nft;
  ValidatorManagerMock public validatorManager;
  NFTStakingManager public nftStakingManager;
  LicenseVault public licenseVault;

  address public admin;
  address public deployer;

  function setUp() public override {
    super.setUp();
    admin = getActor("Admin");
    deployer = getActor("Deployer");

    vm.startPrank(deployer);

    validatorManager = new ValidatorManagerMock();
    nft = new ERC721Mock("NFT License", "NFTL");

    NFTStakingManager nftImpl = new NFTStakingManager();
    ERC1967Proxy nftProxy = new ERC1967Proxy(
      address(nftImpl), abi.encodeCall(NFTStakingManager.initialize, _defaultNFTStakingManagerSettings(address(validatorManager), address(nft)))
    );
    nftStakingManager = NFTStakingManager(address(nftProxy));

    LicenseVault licenseVaultImpl = new LicenseVault();
    ERC1967Proxy licenseVaultProxy = new ERC1967Proxy(
      address(licenseVaultImpl),
      abi.encodeCall(LicenseVault.initialize, (address(nft), address(nftStakingManager), admin, DEFAULT_P_CHAIN_OWNER, DEFAULT_P_CHAIN_OWNER))
    );
    licenseVault = LicenseVault(address(licenseVaultProxy));

    vm.stopPrank();
  }

  function test_initiateValidatorRegistration() public {
    address validator = getActor("Validator");
    nft.mint(validator, 1);

    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = 1;

    vm.startPrank(validator);
    nft.setApprovalForAll(address(licenseVault), true);
    licenseVault.deposit(tokenIds);
    vm.stopPrank();

    assertEq(nft.balanceOf(validator), 0);
    assertEq(licenseVault.balanceOf(validator), 1);
  }

  function _defaultNFTStakingManagerSettings(address validatorManager_, address license_) internal view returns (NFTStakingManagerSettings memory) {
    return NFTStakingManagerSettings({
      validatorManager: validatorManager_,
      license: license_,
      initialEpochTimestamp: uint32(block.timestamp),
      epochDuration: 1 days,
      licenseWeight: 1000,
      epochRewards: 1000 ether,
      maxLicensesPerValidator: 10
    });
  }
}
