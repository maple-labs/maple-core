// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "lib/openzeppelin-contracts/contracts/math/Math.sol";
import "lib/openzeppelin-contracts/contracts/math/SafeMath.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/SafeERC20.sol";

import "external-interfaces/IERC2258.sol";

import "./interfaces/IMplRewards.sol";

// https://docs.synthetix.io/contracts/source/contracts/stakingrewards
/// @title MplRewards Synthetix farming contract fork for liquidity mining.
contract MplRewards is IMplRewards, Ownable {

    using SafeMath  for uint256;
    using SafeERC20 for IERC20;

    IERC20    public override immutable rewardsToken;
    IERC2258  public override immutable stakingToken;

    uint256 public override periodFinish;
    uint256 public override rewardRate;
    uint256 public override rewardsDuration;
    uint256 public override lastUpdateTime;
    uint256 public override rewardPerTokenStored;
    uint256 public override lastPauseTime;
    bool    public override paused;

    mapping(address => uint256) public override userRewardPerTokenPaid;
    mapping(address => uint256) public override rewards;

    uint256 private _totalSupply;

    mapping(address => uint256) private _balances;

    constructor(address _rewardsToken, address _stakingToken, address _owner) public {
        rewardsToken    = IERC20(_rewardsToken);
        stakingToken    = IERC2258(_stakingToken);
        rewardsDuration = 7 days;
        transferOwnership(_owner);
    }

    function _updateReward(address account) internal {
        uint256 _rewardPerTokenStored = rewardPerToken();
        rewardPerTokenStored          = _rewardPerTokenStored;
        lastUpdateTime                = lastTimeRewardApplicable();

        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = _rewardPerTokenStored;
        }
    }

    function _notPaused() internal view {
        require(!paused, "R:PAUSED");
    }

    function totalSupply() external override view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external override view returns (uint256) {
        return _balances[account];
    }

    function lastTimeRewardApplicable() public override view returns (uint256) {
        return Math.min(block.timestamp, periodFinish);
    }

    function rewardPerToken() public override view returns (uint256) {
        return _totalSupply == 0
            ? rewardPerTokenStored
            : rewardPerTokenStored.add(
                  lastTimeRewardApplicable().sub(lastUpdateTime).mul(rewardRate).mul(1e18).div(_totalSupply)
              );
    }

    function earned(address account) public override view returns (uint256) {
        return _balances[account].mul(rewardPerToken().sub(userRewardPerTokenPaid[account])).div(1e18).add(rewards[account]);
    }

    function getRewardForDuration() external override view returns (uint256) {
        return rewardRate.mul(rewardsDuration);
    }

    function stake(uint256 amount) external override {
        _notPaused();
        _updateReward(msg.sender);
        uint256 newBalance = _balances[msg.sender].add(amount);
        require(amount > 0, "R:ZERO_STAKE");
        require(stakingToken.custodyAllowance(msg.sender, address(this)) >= newBalance, "R:INSUF_CUST_ALLOWANCE");
        _totalSupply          = _totalSupply.add(amount);
        _balances[msg.sender] = newBalance;
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) public override {
        _notPaused();
        _updateReward(msg.sender);
        require(amount > 0, "R:ZERO_WITHDRAW");
        _totalSupply = _totalSupply.sub(amount);
        _balances[msg.sender] = _balances[msg.sender].sub(amount);
        stakingToken.transferByCustodian(msg.sender, msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    function getReward() public override {
        _notPaused();
        _updateReward(msg.sender);
        uint256 reward = rewards[msg.sender];

        if (reward == uint256(0)) return;

        rewards[msg.sender] = uint256(0);
        rewardsToken.safeTransfer(msg.sender, reward);
        emit RewardPaid(msg.sender, reward);
    }

    function exit() external override {
        withdraw(_balances[msg.sender]);
        getReward();
    }

    function notifyRewardAmount(uint256 reward) external override onlyOwner {
        _updateReward(address(0));

        uint256 _rewardRate = block.timestamp >= periodFinish
            ? reward.div(rewardsDuration)
            : reward.add(
                  periodFinish.sub(block.timestamp).mul(rewardRate)
              ).div(rewardsDuration);

        rewardRate = _rewardRate;

        // Ensure the provided reward amount is not more than the balance in the contract.
        // This keeps the reward rate in the right range, preventing overflows due to
        // very high values of rewardRate in the earned and rewardsPerToken functions;
        // Reward + leftover must be less than 2^256 / 10^18 to avoid overflow.
        uint256 balance = rewardsToken.balanceOf(address(this));
        require(_rewardRate <= balance.div(rewardsDuration), "R:REWARD_TOO_HIGH");

        lastUpdateTime = block.timestamp;
        periodFinish   = block.timestamp.add(rewardsDuration);
        emit RewardAdded(reward);
    }

    function updatePeriodFinish(uint256 timestamp) external override onlyOwner {
        _updateReward(address(0));
        periodFinish = timestamp;
    }

    function recoverERC20(address tokenAddress, uint256 tokenAmount) external override onlyOwner {
        IERC20(tokenAddress).safeTransfer(owner(), tokenAmount);
        emit Recovered(tokenAddress, tokenAmount);
    }

    function setRewardsDuration(uint256 _rewardsDuration) external override onlyOwner {
        require(block.timestamp > periodFinish, "R:PERIOD_NOT_FINISHED");
        rewardsDuration = _rewardsDuration;
        emit RewardsDurationUpdated(rewardsDuration);
    }

    function setPaused(bool _paused) external override onlyOwner {
        // Ensure we're actually changing the state before we do anything
        require(_paused != paused, "R:ALREADY_SET");

        // Set our paused state.
        paused = _paused;

        // If applicable, set the last pause time.
        if (_paused) lastPauseTime = block.timestamp;

        // Let everyone know that our pause state has changed.
        emit PauseChanged(paused);
    }

}
