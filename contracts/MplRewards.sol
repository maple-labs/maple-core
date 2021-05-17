// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "./interfaces/IERC2258.sol";

// https://docs.synthetix.io/contracts/source/contracts/stakingrewards
/// @title MplRewards Synthetix farming contract fork for liquidity mining.
contract MplRewards is Ownable {

    using SafeMath  for uint256;
    using SafeERC20 for IERC20;

    IERC20    public immutable rewardsToken;
    IERC2258  public immutable stakingToken;

    uint256 public periodFinish;
    uint256 public rewardRate;
    uint256 public rewardsDuration;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    uint256 public lastPauseTime;
    bool    public paused;

    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    uint256 private _totalSupply;

    mapping(address => uint256) private _balances;

    event            RewardAdded(uint256 reward);
    event                 Staked(address indexed account, uint256 amount);
    event              Withdrawn(address indexed account, uint256 amount);
    event             RewardPaid(address indexed account, uint256 reward);
    event RewardsDurationUpdated(uint256 newDuration);
    event              Recovered(address token, uint256 amount);
    event           PauseChanged(bool isPaused);

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

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        return Math.min(block.timestamp, periodFinish);
    }

    function rewardPerToken() public view returns (uint256) {
        return _totalSupply == 0
            ? rewardPerTokenStored
            : rewardPerTokenStored.add(
                  lastTimeRewardApplicable().sub(lastUpdateTime).mul(rewardRate).mul(1e18).div(_totalSupply)
              );
    }

    function earned(address account) public view returns (uint256) {
        return _balances[account].mul(rewardPerToken().sub(userRewardPerTokenPaid[account])).div(1e18).add(rewards[account]);
    }

    function getRewardForDuration() external view returns (uint256) {
        return rewardRate.mul(rewardsDuration);
    }

    /**
        @dev It emits a `Staked` event.
    */
    function stake(uint256 amount) external {
        _notPaused();
        _updateReward(msg.sender);
        uint256 newBalance = _balances[msg.sender].add(amount);
        require(amount > 0, "R:ZERO_STAKE");
        require(stakingToken.custodyAllowance(msg.sender, address(this)) >= newBalance, "R:INSUF_CUST_ALLOWANCE");
        _totalSupply          = _totalSupply.add(amount);
        _balances[msg.sender] = newBalance;
        emit Staked(msg.sender, amount);
    }

    /**
        @dev It emits a `Withdrawn` event.
    */
    function withdraw(uint256 amount) public {
        _notPaused();
        _updateReward(msg.sender);
        require(amount > 0, "R:ZERO_WITHDRAW");
        _totalSupply = _totalSupply.sub(amount);
        _balances[msg.sender] = _balances[msg.sender].sub(amount);
        stakingToken.transferByCustodian(msg.sender, msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    /**
        @dev It emits a `RewardPaid` event if any rewards are received.
    */
    function getReward() public {
        _notPaused();
        _updateReward(msg.sender);
        uint256 reward = rewards[msg.sender];

        if (reward == uint256(0)) return;

        rewards[msg.sender] = uint256(0);
        rewardsToken.safeTransfer(msg.sender, reward);
        emit RewardPaid(msg.sender, reward);
    }

    function exit() external {
        withdraw(_balances[msg.sender]);
        getReward();
    }

    /**
        @dev Only the contract Owner may call this.
        @dev It emits a `RewardAdded` event.
    */
    function notifyRewardAmount(uint256 reward) external onlyOwner {
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

    /**
        @dev End rewards emission earlier. Only the contract Owner may call this.
    */
    function updatePeriodFinish(uint256 timestamp) external onlyOwner {
        _updateReward(address(0));
        periodFinish = timestamp;
    }

    /**
        @dev Added to support recovering tokens unintentionally sent to this contract.
             Only the contract Owner may call this.
        @dev It emits a `Recovered` event.
    */
    function recoverERC20(address tokenAddress, uint256 tokenAmount) external onlyOwner {
        IERC20(tokenAddress).safeTransfer(owner(), tokenAmount);
        emit Recovered(tokenAddress, tokenAmount);
    }

    /**
        @dev Only the contract Owner may call this.
        @dev It emits a `RewardsDurationUpdated` event.
    */
    function setRewardsDuration(uint256 _rewardsDuration) external onlyOwner {
        require(block.timestamp > periodFinish, "R:PERIOD_NOT_FINISHED");
        rewardsDuration = _rewardsDuration;
        emit RewardsDurationUpdated(rewardsDuration);
    }

    /**
        @dev Change the paused state of the contract. Only the contract Owner may call this.
        @dev It emits a `PauseChanged` event.
    */
    function setPaused(bool _paused) external onlyOwner {
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
