contract NFTStakingIdea {
  uint32 public constant EPOCH_DURATION = 1 days;
  uint256 public constant EPOCH_REWARDS = 2_500_000_000 ether / (365 * 5);

  // Track global epoch stats accross all validators

  struct epochInfo {
    uint256 totalStakedLicenses;
  }

  mapping(uint32 epochNumber => epochInfo) public epochInfos;

  // We dont xfer nft to this contract, we just mark it as locked
  mapping(uint256 tokenId => bytes32 stakeID) public tokenLockedBy;

  struct stakerInfo {
    address owner;
    bytes32 validationId;
    uint256[] tokenIds;
    uint32 startEpoch;
    uint32 endEpoch;
    mapping(uint32 epochNumber => uint256 rewards) claimableRewardsPerEpoch; // will get set to zero when claimed
  }

  // stakeId = validationId but in future could also be delegationId if we support that
  mapping(bytes32 stakeId => stakerInfo) public stakerInfos;

  // Ensure that we only ever mint rewards once for a given epochNumber/tokenId combo
  // Gas is cheap so nesting mapping is the clearest
  mapping(uint32 epochNumber => mapping(uint256 tokenId => bool isRewardsMinted)) public isRewardsMinted;

  // MAIN STAKING ENTRYPOINT
  function initializeValidatorRegistration(ValidatorRegistrationInput calldata registrationInput, uint256[] calldata tokenIDs) {
    uint256 weight = convertLicensesToWeight(tokenIDs);
    bytes32 validationID = validatorManager.initializeValidatorRegistration(registrationInput, weight);
    // do not xfer, just mark tokens as locked by this stakeId
    _lockTokens(tokenIDs, validationID);
    // create stakerInfo and add to mapping
    stakerInfos[validationID] = stakerInfo({
      owner: msg.sender,
      validationId: validationID,
      tokenIds: tokenIDs,
      claimableRewardsPerEpoch: new mapping(uint32 epochNumber => uint256 rewards)()
    });
  }

  function completeValidatorRegistration(uint32 messageIndex) {
    stakerInfo storage staker = stakerInfos[validationID];
    epochInfos[getCurrentEpoch()].totalStakedLicenses += tokenIDs.length;
    staker.startEpoch = getCurrentEpoch();
    validatorManager.completeValidatorRegistration(messageIndex);
  }
  // frak how to track across epochs

  function initializeEndValidation(bytes32 validationID) {
    stakerInfo storage staker = stakerInfos[stakeId];
    if (stakeInfo.owner != _msgSender()) revert InvalidOwner(_msgSender());
    staker.endEpoch = getCurrentEpoch();
    epochInfos[getCurrentEpoch()].totalStakedLicenses -= staker.tokenIds.length;
    validatorManager.initializeEndValidation(validationID);
  }

  function completeEndValidation(uint32 messageIndex) {
    _unlockTokens(staker.tokenIds);
    validatorManager.completeEndValidation(messageIndex);
  }

  function rewardsSnapshot() {}

  // Anyone can call this function to mint rewards (prob backend cron process)
  // In future this could accept uptime proof as well.
  function mintRewards(bytes32 stakeId, uint32 epochNumber) external {
    stakerInfo storage staker = stakerInfos[stakeId];
    if (getCurrentEpoch() < staker.startEpoch) revert("Cannot mint rewards before start epoch");
    if (getCurrentEpoch() > staker.endEpoch) revert("Cannot mint rewards after end epoch");
    for (uint256 i = 0; i < staker.tokenIds.length; i++) {
      if (tokenLockedBy[staker.tokenIds[i]] != stakeId) revert("Token not locked by this stakeId");
      if (isRewardsMinted[epochNumber][staker.tokenIds[i]]) revert("Rewards already minted for this tokenId");
      isRewardsMinted[epochNumber][staker.tokenIds[i]] = true;
    }
    uint256 rewards = calculateRewardsPerLicense(epochNumber) * staker.tokenIds.length;
    staker.claimableRewardsPerEpoch[epochNumber] = rewards;
    // mint rewards using nativeminter
    emit RewardsMinted(stakeId, epochNumber, rewards);
  }

  function claimRewards(bytes32 stakeId, uint32[] epochNumbers) external {
    stakerInfo storage staker = stakerInfos[stakeId];
    if (stakeInfo.owner != _msgSender()) revert InvalidOwner(_msgSender());
    uint256 totalRewards = 0;
    for (uint32 i = 0; i < epochNumbers.length; i++) {
      uint256 rewards = staker.claimableRewardsPerEpoch[epochNumbers[i]];
      staker.claimableRewardsPerEpoch[epochNumbers[i]] = 0;
      emit RewardsClaimed(stakeId, epochNumbers[i], rewards);
      totalRewards += rewards;
    }
    payable(staker.owner).safeTransfer(totalRewards);
  }

  function calculateRewardsPerLicense(uint32 epochNumber) public view returns (uint256) {
    return EPOCH_REWARDS / epochInfos[epochNumber].totalStakedLicenses;
  }

  function _lockTokens(uint256[] tokenIDs, bytes32 stakeId) internal {
    for (uint256 i = 0; i < tokenIDs.length; i++) {
      uint256 tokenID = tokenIDs[i];
      address owner = NFT.ownerOf(tokenID);
      if (owner != _msgSender()) revert UnauthorizedOwner(owner);
      if (tokenLockedBy[tokenID] != bytes32(0)) revert TokenAlreadyLocked(tokenID);
      tokenLockedBy[tokenID] = stakeId;
    }
  }

  function _unlockTokens(uint256[] tokenIDs) internal {
    for (uint256 i = 0; i < tokenIDs.length; i++) {
      tokenLockedBy[tokenIDs[i]] = bytes32(0);
    }
  }

  // HELPERS

  function getEpochByTimestamp(uint32 timestamp) public view returns (uint32) {
    return (timestamp - initialEpochTimestamp) / epochDuration;
  }

  function getCurrentEpoch() public view returns (uint32) {
    return getEpochByTimestamp(uint32(block.timestamp));
  }
}
