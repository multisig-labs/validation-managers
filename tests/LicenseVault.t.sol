// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.25;

import {Base} from "./utils/Base.sol";

import {LicenseVault} from "../contracts/LicenseVault.sol";
import {NFTStakingManager, NFTStakingManagerSettings, StakeInfoView} from "../contracts/NFTStakingManager.sol";

import {NativeMinterMock} from "../contracts/mocks/NativeMinterMock.sol";
import {ValidatorManagerMock} from "../contracts/mocks/ValidatorManagerMock.sol";
import {NodeLicense} from "../contracts/tokens/NodeLicense.sol";
import {ReceiptToken} from "../contracts/tokens/ReceiptToken.sol";
import {ERC1967Proxy} from "@openzeppelin-contracts-5.2.0/proxy/ERC1967/ERC1967Proxy.sol";
import {console2} from "forge-std-1.9.6/src/console2.sol";
import {PChainOwner} from "icm-contracts-8817f47/contracts/validator-manager/ACP99Manager.sol";

contract LicenseVaultTest is Base {
  NodeLicense public nodeLicense;
  ReceiptToken public receiptToken;
  ValidatorManagerMock public validatorManager;
  NFTStakingManager public nftStakingManager;
  LicenseVault public licenseVault;

  address public admin;

  function setUp() public override {
    super.setUp();
    admin = getActor("Admin");

    validatorManager = new ValidatorManagerMock();

    NodeLicense nodeLicenseImpl = new NodeLicense();
    ERC1967Proxy nodeLicenseProxy =
      new ERC1967Proxy(address(nodeLicenseImpl), abi.encodeCall(NodeLicense.initialize, (admin, admin, 0, "NFT License", "NFTL", "")));
    nodeLicense = NodeLicense(address(nodeLicenseProxy));

    ReceiptToken receiptImpl = new ReceiptToken();
    ERC1967Proxy receiptProxy = new ERC1967Proxy(address(receiptImpl), abi.encodeCall(ReceiptToken.initialize, (admin, admin, "Receipt", "REC", "")));
    receiptToken = ReceiptToken(address(receiptProxy));

    NFTStakingManager nftImpl = new NFTStakingManager();
    ERC1967Proxy nftProxy = new ERC1967Proxy(
      address(nftImpl),
      abi.encodeCall(NFTStakingManager.initialize, _defaultNFTStakingManagerSettings(address(validatorManager), address(nodeLicense)))
    );
    nftStakingManager = NFTStakingManager(address(nftProxy));

    LicenseVault licenseVaultImpl = new LicenseVault();
    ERC1967Proxy licenseVaultProxy = new ERC1967Proxy(
      address(licenseVaultImpl),
      abi.encodeCall(
        LicenseVault.initialize,
        (address(nodeLicense), address(receiptToken), address(nftStakingManager), admin, DEFAULT_P_CHAIN_OWNER, DEFAULT_P_CHAIN_OWNER)
      )
    );
    licenseVault = LicenseVault(payable(address(licenseVaultProxy)));

    vm.startPrank(admin);
    receiptToken.grantRole(receiptToken.MINTER_ROLE(), address(licenseVault));
    NativeMinterMock nativeMinter = new NativeMinterMock();
    vm.etch(0x0200000000000000000000000000000000000001, address(nativeMinter).code);
  }

  function test_deposit_withdraw() public {
    address validator = getActor("Validator");
    uint256[] memory tokenIds = mintNodeLicenses(validator, 10);

    vm.startPrank(validator);

    nodeLicense.setApprovalForAll(address(licenseVault), true);
    licenseVault.deposit(tokenIds);

    assertEq(nodeLicense.balanceOf(validator), 0);
    assertEq(licenseVault.balanceOf(validator), 10);
    assertEq(receiptToken.balanceOf(validator), 1);

    vm.expectRevert(LicenseVault.NoWithdrawalRequest.selector);
    licenseVault.completeWithdrawal();

    vm.expectRevert(LicenseVault.NotEnoughLicenses.selector);
    licenseVault.requestWithdrawal(11);

    licenseVault.requestWithdrawal(10);
    licenseVault.completeWithdrawal();

    assertEq(licenseVault.balanceOf(validator), 0);
    assertEq(nodeLicense.balanceOf(validator), 10);
    assertEq(receiptToken.balanceOf(validator), 0);
  }

  function test_stake_unstake() public {
    address validator = getActor("Validator");
    address unpriviledged = getActor("unpriviledged");
    uint256[] memory tokenIds = mintNodeLicenses(validator, 10);

    vm.startPrank(validator);
    nodeLicense.setApprovalForAll(address(licenseVault), true);
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
    assertEq(stakeInfoView.startEpoch, 0);
    assertEq(stakeInfoView.endEpoch, 0);
    assertEq(stakeInfoView.tokenIds.length, 10);

    vm.startPrank(unpriviledged);
    nftStakingManager.completeValidatorRegistration(0);
    assertEq(nftStakingManager.getCurrentTotalStakedLicenses(), 10);
    assertEq(nftStakingManager.getTokenLockedBy(tokenIds[0]), stakeId);
    stakeInfoView = nftStakingManager.getStakeInfoView(stakeId);
    assertEq(stakeInfoView.owner, address(licenseVault));
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

    vm.startPrank(unpriviledged);
    nftStakingManager.completeValidatorRemoval(0);
    stakeInfoView = nftStakingManager.getStakeInfoView(stakeId);
    assertEq(nftStakingManager.getTokenLockedBy(tokenIds[0]), bytes32(0));
  }

  function test_stake_claim_rewards() public {
    address depositor = getActor("Depositor");
    address unpriviledged = getActor("Unpriviledged");
    uint256[] memory tokenIds = mintNodeLicenses(depositor, 10);

    skip(1 days);

    vm.startPrank(depositor);
    nodeLicense.setApprovalForAll(address(licenseVault), true);
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

  function test_fullCycleRewards() public {
    uint256 expectedRewards = 1000 ether;
    vm.warp(100 seconds);
    vm.warp(1 days + block.timestamp);
    address validator = getActor("Validator");
    uint256[] memory tokenIds = mintNodeLicenses(validator, 10);

    vm.startPrank(validator);
    nodeLicense.setApprovalForAll(address(licenseVault), true);
    licenseVault.deposit(tokenIds);

    vm.startPrank(admin);
    bytes32 stakeId = licenseVault.stakeValidator(DEFAULT_NODE_ID, DEFAULT_BLS_PUBLIC_KEY, DEFAULT_BLS_POP, 10);
    nftStakingManager.completeValidatorRegistration(0);
    vm.stopPrank();

    StakeInfoView memory stakeInfoView = nftStakingManager.getStakeInfoView(stakeId);

    bytes32[] memory stakeIds = new bytes32[](1);
    stakeIds[0] = stakeId;

    uint32 epoch = nftStakingManager.getCurrentEpoch();

    // skip ahead to the next epoch, so we can track rewards for the previous epoch
    vm.warp(1 days + block.timestamp);
    uint32 currentEpoch = nftStakingManager.getCurrentEpoch();
    uint32 lastEpoch = currentEpoch - 1;
    nftStakingManager.rewardsSnapshot();
    nftStakingManager.mintRewards(lastEpoch, stakeIds);

    uint256 vaultBalanceBefore = address(licenseVault).balance;

    vm.startPrank(admin);
    licenseVault.claimValidatorRewards(stakeId, 1);

    uint256 vaultBalanceAfter = address(licenseVault).balance;
    assertEq(vaultBalanceAfter, vaultBalanceBefore + expectedRewards);


    assertEq(licenseVault.getClaimableRewards(validator), expectedRewards);

    vm.startPrank(validator);
    licenseVault.claimDepositorRewards();
    assertEq(validator.balance, expectedRewards);
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

  function mintNodeLicenses(address to, uint256 amount) internal returns (uint256[] memory) {
    vm.startPrank(admin);
    uint256[] memory tokenIds = new uint256[](amount);
    for (uint256 i = 0; i < amount; i++) {
      tokenIds[i] = nodeLicense.mint(to);
    }
    vm.stopPrank();
    return tokenIds;
  }
}
