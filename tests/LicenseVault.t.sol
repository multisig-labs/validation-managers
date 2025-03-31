// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

import {Base} from "./utils/Base.sol";

import {LicenseVault} from "../contracts/LicenseVault.sol";
import {NFTStakingManager, NFTStakingManagerSettings, StakeInfoView} from "../contracts/NFTStakingManager.sol";
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

  function test_deposit_withdraw() public {
    address validator = getActor("Validator");
    uint256[] memory tokenIds = nft.batchMint(validator, 10);

    vm.startPrank(validator);

    nft.setApprovalForAll(address(licenseVault), true);
    licenseVault.deposit(tokenIds);

    assertEq(nft.balanceOf(validator), 0);
    assertEq(licenseVault.balanceOf(validator), 10);

    vm.expectRevert(LicenseVault.NoWithdrawalRequest.selector);
    licenseVault.completeWithdrawal();

    vm.expectRevert(LicenseVault.NotEnoughLicenses.selector);
    licenseVault.requestWithdrawal(11);

    licenseVault.requestWithdrawal(10);
    licenseVault.completeWithdrawal();

    assertEq(licenseVault.balanceOf(validator), 0);
    assertEq(nft.balanceOf(validator), 10);
  }

  function test_stake_unstake() public {
    address validator = getActor("Validator");
    address unprivledged = getActor("unprivledged");
    uint256[] memory tokenIds = nft.batchMint(validator, 10);

    vm.startPrank(validator);
    nft.setApprovalForAll(address(licenseVault), true);
    licenseVault.deposit(tokenIds);

    vm.startPrank(admin);
    vm.expectRevert(LicenseVault.NotEnoughLicenses.selector);
    bytes32 stakeId = licenseVault.stakeValidator(DEFAULT_NODE_ID, DEFAULT_BLS_PUBLIC_KEY, DEFAULT_BLS_POP, 11);

    stakeId = licenseVault.stakeValidator(DEFAULT_NODE_ID, DEFAULT_BLS_PUBLIC_KEY, DEFAULT_BLS_POP, 10);
    // validator is in pending state...
    assertEq(nftStakingManager.getCurrentTotalStakedLicenses(), 0);
    assertEq(nftStakingManager.getTokenLockedBy(tokenIds[0]), stakeId);
    StakeInfoView memory stakeInfoView = nftStakingManager.getStakeInfoView(stakeId);
    assertEq(stakeInfoView.owner, address(licenseVault));
    assertEq(stakeInfoView.validationId, stakeId);
    assertEq(stakeInfoView.startEpoch, 0);
    assertEq(stakeInfoView.endEpoch, 0);
    assertEq(stakeInfoView.tokenIds.length, 10);

    vm.startPrank(unprivledged);
    nftStakingManager.completeValidatorRegistration(0);
    assertEq(nftStakingManager.getCurrentTotalStakedLicenses(), 10);
    assertEq(nftStakingManager.getTokenLockedBy(tokenIds[0]), stakeId);
    stakeInfoView = nftStakingManager.getStakeInfoView(stakeId);
    assertEq(stakeInfoView.owner, address(licenseVault));
    assertEq(stakeInfoView.validationId, stakeId);
    assertEq(stakeInfoView.startEpoch, nftStakingManager.getCurrentEpoch());
    assertEq(stakeInfoView.endEpoch, 0);
    assertEq(stakeInfoView.tokenIds.length, 10);

    // Unstake
    vm.startPrank(admin);
    licenseVault.unstakeValidator(stakeId);
    assertEq(nftStakingManager.getCurrentTotalStakedLicenses(), 0);
    stakeInfoView = nftStakingManager.getStakeInfoView(stakeId);
    assertEq(stakeInfoView.endEpoch, nftStakingManager.getCurrentEpoch());
    assertEq(stakeInfoView.tokenIds.length, 10);
    assertEq(nftStakingManager.getTokenLockedBy(tokenIds[0]), stakeId);

    vm.startPrank(unprivledged);
    nftStakingManager.completeValidatorRemoval(0);
    stakeInfoView = nftStakingManager.getStakeInfoView(stakeId);
    assertEq(nftStakingManager.getTokenLockedBy(tokenIds[0]), bytes32(0));
  }

  function test_stake_claim_rewards() public {
    address depositor = getActor("Depositor");
    address unprivledged = getActor("Unprivledged");
    uint256[] memory tokenIds = nft.batchMint(depositor, 10);

    skip(1 days);

    vm.startPrank(depositor);
    nft.setApprovalForAll(address(licenseVault), true);
    licenseVault.deposit(tokenIds);

    vm.startPrank(admin);
    bytes32 stakeId = licenseVault.stakeValidator(DEFAULT_NODE_ID, DEFAULT_BLS_PUBLIC_KEY, DEFAULT_BLS_POP, 10);
    nftStakingManager.completeValidatorRegistration(0);

    skip(1 days);
    nftStakingManager.rewardsSnapshot();
    bytes32[] memory stakeIds = new bytes32[](1);
    stakeIds[0] = stakeId;
    nftStakingManager.mintRewards(1, stakeIds);

    licenseVault.claimValidatorRewards(stakeId, 10);
    assertEq(licenseVault.getClaimableRewards(depositor), 1000 ether);
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
