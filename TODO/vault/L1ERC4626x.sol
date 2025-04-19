// SPDX-License-Identifier: MIT
// Rewards logic inspired by xERC20 (https://github.com/ZeframLou/playpen/blob/main/src/xERC20.sol)

pragma solidity ^0.8.0;

import { SafeERC20 } from "@openzeppelin-contracts-5.3.0/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin-contracts-upgradeable-5.3.0/token/ERC20/IERC20.sol";
import { ERC4626Upgradeable } from
  "@openzeppelin-contracts-upgradeable-5.3.0/token/ERC20/extensions/ERC4626Upgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import { FixedPointMathLib } from "solmate-6.8.0/src/utils/FixedPointMathLib.sol";
import { SafeCastLib } from "solmate-6.8.0/src/utils/SafeCastLib.sol";
import { SafeTransferLib } from "solmate-6.8.0/src/utils/SafeTransferLib.sol";

contract L1ERC4626x is Initializable, ERC4626Upgradeable {
  using SafeCastLib for *;
  using FixedPointMathLib for uint256;

  error SyncError();
  error ZeroShares();
  error ZeroAssets();
  error InvalidStakingDeposit();

  event NewRewardsCycle(uint256 indexed cycleEnd, uint256 rewardsAmt);
  event WithdrawnForStaking(address indexed caller, uint256 assets);
  event DepositedFromStaking(address indexed caller, uint256 baseAmt, uint256 rewardsAmt);

  /// @notice the effective start of the current cycle
  uint32 public lastSync;

  /// @notice the maximum length of a rewards cycle
  uint32 public rewardsCycleLength;

  /// @notice the end of the current cycle. Will always be evenly divisible by `rewardsCycleLength`.
  uint32 public rewardsCycleEnd;

  /// @notice the amount of rewards distributed in a the most recent cycle.
  uint192 public lastRewardsAmt;

  /// @notice the total amount of avax (including avax sent out for staking and all incoming rewards)
  uint256 public totalReleasedAssets;

  /// @notice total amount of avax currently out for staking (not including any rewards)
  uint256 public stakingTotalAssets;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    // The constructor is executed only when creating implementation contract
    // so prevent it's reinitialization
    _disableInitializers();
  }

  function initialize(IERC20 _asset, uint32 _rewardsCycleLength, uint256 _initialDeposit)
    public
    initializer
  {
    __ERC4626_init(_asset);

    // sacrifice initial seed of shares to prevent front-running early deposits
    if (_initialDeposit > 0) {
      deposit(_initialDeposit, address(this));
    }
    rewardsCycleLength = _rewardsCycleLength;
    // Ensure it will be evenly divisible by `rewardsCycleLength`.
    rewardsCycleEnd = (block.timestamp.safeCastTo32() / rewardsCycleLength) * rewardsCycleLength;
  }

  /// @notice Distributes rewards to TokenggAVAX holders. Public, anyone can call.
  /// 				All surplus `asset` balance of the contract over the internal balance becomes queued for the next cycle.
  function syncRewards() public {
    uint32 timestamp = block.timestamp.safeCastTo32();

    if (timestamp < rewardsCycleEnd) {
      revert SyncError();
    }

    uint192 lastRewardsAmt_ = lastRewardsAmt;
    uint256 totalReleasedAssets_ = totalReleasedAssets;
    uint256 stakingTotalAssets_ = stakingTotalAssets;

    uint256 nextRewardsAmt = (asset.balanceOf(address(this)) + stakingTotalAssets_)
      - totalReleasedAssets_ - lastRewardsAmt_;

    // Ensure nextRewardsCycleEnd will be evenly divisible by `rewardsCycleLength`.
    uint32 nextRewardsCycleEnd =
      ((timestamp + rewardsCycleLength) / rewardsCycleLength) * rewardsCycleLength;

    lastRewardsAmt = nextRewardsAmt.safeCastTo192();
    lastSync = timestamp;
    rewardsCycleEnd = nextRewardsCycleEnd;
    totalReleasedAssets = totalReleasedAssets_ + lastRewardsAmt_;
    emit NewRewardsCycle(nextRewardsCycleEnd, nextRewardsAmt);
  }

  /// @notice Compute the amount of tokens available to share holders.
  ///         Increases linearly during a reward distribution period from the sync call, not the cycle start.
  /// @return The amount of ggAVAX tokens available
  function totalAssets() public view override returns (uint256) {
    // cache global vars
    uint256 totalReleasedAssets_ = totalReleasedAssets;
    uint192 lastRewardsAmt_ = lastRewardsAmt;
    uint32 rewardsCycleEnd_ = rewardsCycleEnd;
    uint32 lastSync_ = lastSync;

    if (block.timestamp >= rewardsCycleEnd_) {
      // no rewards or rewards are fully unlocked
      // entire reward amount is available
      return totalReleasedAssets_ + lastRewardsAmt_;
    }

    // rewards are not fully unlocked
    // return unlocked rewards and stored total
    uint256 unlockedRewards =
      (lastRewardsAmt_ * (block.timestamp - lastSync_)) / (rewardsCycleEnd_ - lastSync_);
    return totalReleasedAssets_ + unlockedRewards;
  }

  /// @notice Returns the AVAX amount that is available for staking on minipools
  /// @return uint256 AVAX available for staking
  function amountAvailableForStaking() public view returns (uint256) {
    // TODO
    uint256 targetCollateralRate = 0;

    uint256 totalAssets_ = totalAssets();

    uint256 reservedAssets = totalAssets_.mulDivDown(targetCollateralRate, 1 ether);

    if (reservedAssets + stakingTotalAssets > totalAssets_) {
      return 0;
    }
    return totalAssets_ - reservedAssets - stakingTotalAssets;
  }

  /// @notice Accepts AVAX deposit from a minipool. Expects the base amount and rewards earned from staking
  /// @param baseAmt The amount of liquid staker AVAX used to create a minipool
  /// @param rewardAmt The rewards amount (in AVAX) earned from staking
  function depositFromStaking(uint256 baseAmt, uint256 rewardAmt) public {
    uint256 totalAmt = msg.value;
    if (totalAmt != (baseAmt + rewardAmt) || baseAmt > stakingTotalAssets) {
      revert InvalidStakingDeposit();
    }

    emit DepositedFromStaking(msg.sender, baseAmt, rewardAmt);
    stakingTotalAssets -= baseAmt;
    IWAVAX(address(asset)).deposit{ value: totalAmt }();
  }

  /// @notice Allows the MinipoolManager contract to withdraw liquid staker funds to create a minipool
  /// @param assets The amount of AVAX to withdraw
  function withdrawForStaking(uint256 assets) public {
    emit WithdrawnForStaking(msg.sender, assets);

    stakingTotalAssets += assets;
    ERC4626Storage storage $ = _getERC4626Storage();
    SafeERC20.safeTransfer($._asset, msg.sender, assets);
  }

  /// @notice Max assets an owner can deposit
  /// @param _owner User wallet address
  /// @return The max amount of ggAVAX an owner can deposit
  function maxDeposit(address _owner) public view override returns (uint256) {
    return super.maxDeposit(_owner);
  }

  /// @notice Max shares owner can mint
  /// @param _owner User wallet address
  /// @return The max amount of ggAVAX an owner can mint
  function maxMint(address _owner) public view override returns (uint256) {
    return super.maxMint(_owner);
  }

  /// @notice Max assets an owner can withdraw with consideration to liquidity in this contract
  /// @param _owner User wallet address
  /// @return The max amount of ggAVAX an owner can withdraw
  function maxWithdraw(address _owner) public view override returns (uint256) {
    uint256 assets = convertToAssets(balanceOf[_owner]);
    uint256 avail = totalAssets() - stakingTotalAssets;
    return assets > avail ? avail : assets;
  }

  /// @notice Max shares owner can withdraw with consideration to liquidity in this contract
  /// @param _owner User wallet address
  /// @return The max amount of ggAVAX an owner can redeem
  function maxRedeem(address _owner) public view override returns (uint256) {
    uint256 shares = balanceOf[_owner];
    uint256 avail = convertToShares(totalAssets() - stakingTotalAssets);
    return shares > avail ? avail : shares;
  }

  /// @notice Preview shares minted for AVAX deposit
  /// @param assets Amount of AVAX to deposit
  /// @return uint256 Amount of ggAVAX that would be minted
  function previewDeposit(uint256 assets)
    public
    view
    override
    whenTokenNotPaused(assets)
    returns (uint256)
  {
    return super.previewDeposit(assets);
  }

  /// @notice Preview assets required for mint of shares
  /// @param shares Amount of ggAVAX to mint
  /// @return uint256 Amount of AVAX required
  function previewMint(uint256 shares)
    public
    view
    override
    whenTokenNotPaused(shares)
    returns (uint256)
  {
    return super.previewMint(shares);
  }

  /// @notice Function prior to a withdraw
  /// @param amount Amount of AVAX
  function beforeWithdraw(uint256 amount, uint256 /* shares */ ) internal override {
    totalReleasedAssets -= amount;
  }

  /// @notice Function after a deposit
  /// @param amount Amount of AVAX
  function afterDeposit(uint256 amount, uint256 /* shares */ ) internal override {
    totalReleasedAssets += amount;
  }

  // /// @notice Override of ERC20Upgradeable to set the contract version for EIP-2612
  // /// @return hash of this contracts version
  // function versionHash() internal view override returns (bytes32) {
  // 	return keccak256(abi.encodePacked(version));
  // }
}
