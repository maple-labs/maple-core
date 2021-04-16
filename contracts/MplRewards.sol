// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "lib/openzeppelin-contracts/contracts/math/Math.sol";
import "lib/openzeppelin-contracts/contracts/math/SafeMath.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/SafeERC20.sol";
import "./token/FDT.sol";
import "./interfaces/IPool.sol";

// https://docs.synthetix.io/contracts/source/contracts/stakingrewards
/// @title MplRewards Synthetix farming contract fork for liquidity mining.
contract MplRewards is Ownable, FDT {

    using SafeMath  for uint256;
    using SafeERC20 for IERC20;

    IERC20  public immutable rewardsToken;
    IERC20  public immutable stakingToken;

    uint256 public periodFinish;
    uint256 public rewardRate;
    uint256 public rewardsDuration;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    uint256 public lastPauseTime;
    bool    public paused;

    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    uint256 private _totalStake;

    mapping(address => uint256) private _stakes;

    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardsDurationUpdated(uint256 newDuration);
    event Recovered(address token, uint256 amount);
    event PauseChanged(bool isPaused);
    event BalanceUpdated(address indexed who,  address token, uint256 balance);

    constructor(address _rewardsToken, address _stakingToken, address _owner) 
    FDT("MPL Rewards", "rMPL", IPool(_stakingToken).liquidityAsset())
    public 
    {
        rewardsToken    = IERC20(_rewardsToken);
        stakingToken    = IERC20(_stakingToken);
        rewardsDuration = 7 days;
        transferOwnership(_owner);
    }

    function _updateReward(address account) internal {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime       = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
    }

    function _notPaused() internal view {
        require(!paused, "REWARDS:CONTRACT_PAUSED");
    }

    function totalStake() external view returns (uint256) {
        return _totalStake;
    }

    function stakeOf(address account) external view returns (uint256) {
        return _stakes[account];
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        return Math.min(block.timestamp, periodFinish);
    }

    function rewardPerToken() public view returns (uint256) {
        if (_totalStake == 0) return rewardPerTokenStored;
        return
            rewardPerTokenStored.add(
                lastTimeRewardApplicable().sub(lastUpdateTime).mul(rewardRate).mul(1e18).div(_totalStake)
            );
    }

    function _transfer(address from, address to, uint256 amount) internal override {
        revert("MplRewards: Transfers are not allowed");
    }

    function earned(address account) public view returns (uint256) {
        return _stakes[account].mul(rewardPerToken().sub(userRewardPerTokenPaid[account])).div(1e18).add(rewards[account]);
    }

    function getRewardForDuration() external view returns (uint256) {
        return rewardRate.mul(rewardsDuration);
    }

    function stake(uint256 amount) external {
        _notPaused();
        _updateReward(msg.sender);
        require(amount > 0, "REWARDS:STAKE_EQ_ZERO");
        _totalStake = _totalStake.add(amount);
        _stakes[msg.sender] = _stakes[msg.sender].add(amount);
        _mint(msg.sender, amount);
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) public {
        _notPaused();
        _updateReward(msg.sender);
        require(amount > 0, "REWARDS:WITHDRAW_EQ_ZERO");
        _totalStake = _totalStake.sub(amount);
        _stakes[msg.sender] = _stakes[msg.sender].sub(amount);
        withdrawFunds();
        _burn(msg.sender, amount);
        stakingToken.safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    function claimFunds() public {
        IPool(address(stakingToken)).withdrawFunds();
        updateFundsReceived();
    }

    function withdrawFunds() public override {
        // TODO: In Pool we are checking the protocol pause do we want to check here ?
        uint256 withdrawableFunds = _prepareWithdraw();

        if (withdrawableFunds > uint256(0)) {
            // Checking whether the this contract has enough funds to withdraw otherwise claim interest (if > 0) and then withdraw.
            if (fundsTokenBalance < withdrawableFunds && IPool(address(stakingToken)).withdrawableFundsOf(address(this)) > uint256(0)) {
                claimFunds();
            }
            fundsToken.transfer(msg.sender, withdrawableFunds);
            _updateFundsTokenBalance();
            emit BalanceUpdated(address(this), address(fundsToken), fundsTokenBalance);
        }
    }

    function getReward() public {
        _notPaused();
        _updateReward(msg.sender);
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            rewardsToken.safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    function exit() external {
        withdraw(_stakes[msg.sender]);
        getReward();
    }

    function notifyRewardAmount(uint256 reward) external onlyOwner {
        _updateReward(address(0));
        if (block.timestamp >= periodFinish) {
            rewardRate = reward.div(rewardsDuration);
        } else {
            uint256 remaining = periodFinish.sub(block.timestamp);
            uint256 leftover  = remaining.mul(rewardRate);
            rewardRate        = reward.add(leftover).div(rewardsDuration);
        }

        // Ensure the provided reward amount is not more than the balance in the contract.
        // This keeps the reward rate in the right range, preventing overflows due to
        // very high values of rewardRate in the earned and rewardsPerToken functions;
        // Reward + leftover must be less than 2^256 / 10^18 to avoid overflow.
        uint balance = rewardsToken.balanceOf(address(this));
        require(rewardRate <= balance.div(rewardsDuration), "REWARDS:REWARD_TOO_HIGH");

        lastUpdateTime = block.timestamp;
        periodFinish   = block.timestamp.add(rewardsDuration);
        emit RewardAdded(reward);
    }

    // End rewards emission earlier
    function updatePeriodFinish(uint timestamp) external onlyOwner {
        _updateReward(address(0));
        periodFinish = timestamp;
    }

    // Added to support recovering LP Rewards from other systems such as BAL to be distributed to holders
    function recoverERC20(address tokenAddress, uint256 tokenAmount) external onlyOwner {
        require(tokenAddress != address(stakingToken), "REWARDS:CANNOT_RECOVER_STAKE_TOKEN");
        IERC20(tokenAddress).safeTransfer(owner(), tokenAmount);
        emit Recovered(tokenAddress, tokenAmount);
    }

    function setRewardsDuration(uint256 _rewardsDuration) external onlyOwner {
        require(block.timestamp > periodFinish, "REWARDS:PERIOD_NOT_FINISHED");
        rewardsDuration = _rewardsDuration;
        emit RewardsDurationUpdated(rewardsDuration);
    }

    /**
        @dev Change the paused state of the contract. Only the contract owner may call this.
    */
    function setPaused(bool _paused) external onlyOwner {
        // Ensure we're actually changing the state before we do anything
        require(_paused != paused, "MplRewards:ALREADY_IN_SAME_STATE");

        // Set our paused state.
        paused = _paused;

        // If applicable, set the last pause time.
        if (_paused) lastPauseTime = block.timestamp;

        // Let everyone know that our pause state has changed.
        emit PauseChanged(paused);
    }
}
