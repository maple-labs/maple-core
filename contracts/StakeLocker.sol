// SPDX-License-Identifier: MIT

pragma solidity >=0.6.11;

import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "./token/IFundsDistributionToken.sol";
import "./token/FundsDistributionToken.sol";
import "./interfaces/IPool.sol";
import "./interfaces/IGlobals.sol";

/// @title StakeLocker is responsbile for escrowing staked assets and distributing a portion of interest payments.
contract StakeLocker is IFundsDistributionToken, FundsDistributionToken {

    using SafeMathInt    for int256;
    using SignedSafeMath for int256;

    uint256 constant WAD = 10 ** 18;  // Scaling factor for synthetic float division

    address public immutable stakeAsset;      // The asset deposited by stakers into this contract, for liquidation during defaults.
    address public immutable liquidityAsset;  // The LiquidityAsset for the Pool as well as the dividend token for this contract.
    address public immutable owner;           // The parent liquidity pool. (TODO: Consider if this variable is needed, redundant to IParentLP)
    address public immutable globals;         // Maple globals
    
    IERC20 private fundsToken;  // ERC-2222 token used to claim revenues (TODO: Move to FDT)

    uint256 public fundsTokenBalance;  //  The amount of LiquidityAsset tokens (dividends) currently present and accounted for in this contract.

    bool private isLPDefunct;    // The LiquidityAsset for the Pool as well as the dividend token for this contract.
    bool private isLPFinalized;  // The LiquidityAsset for the Pool as well as the dividend token for this contract.

    mapping(address => uint256) private stakeDate;  // Map address to date value (TODO: Consider making public)

    event BalanceUpdated(address who, address token, uint256 balance);

    // TODO: Dynamically assign name and locker to the FundsDistributionToken() params.
    constructor(
        address _stakeAsset,
        address _liquidityAsset,
        address _owner,
        address _globals
    ) FundsDistributionToken("Maple Stake Locker", "MPLSTAKE") public {
        liquidityAsset = _liquidityAsset;
        stakeAsset     = _stakeAsset;
        owner          = _owner;
        globals        = _globals;
        fundsToken     = IERC20(_liquidityAsset);
    }

    event   Stake(uint256 _amount, address _staker);
    event Unstake(uint256 _amount, address _staker);

    modifier delegateLock() {
        require(
            msg.sender != IPool(owner).poolDelegate() || isLPDefunct || !isLPFinalized,
            "StakeLocker:ERR_DELEGATE_STAKE_LOCKED"
        );
        _;
    }

    // TODO: Identify why an error is thrown when console.log() is not present in this modifier.
    modifier isLP() {
        require(msg.sender == owner, "StakeLocker:ERR_UNAUTHORIZED");
        _;
    }
    modifier isGovernor() {
        require(msg.sender == IGlobals(globals).governor(), "msg.sender is not Governor");
        _;
    }

    /**
     * @notice Deposit stakeAsset and mint an equal number of FundsDistributionTokens to the user
     * @param amt Amount of stakeAsset(BPTs) to stake
     */
    function stake(uint256 amt) external {
        require(
            IERC20(stakeAsset).transferFrom(msg.sender, address(this), amt),
            "StakeLocker:ERR_INSUFFICIENT_APPROVED_FUNDS"
        );
        _updateStakeDate(msg.sender, amt);
        _mint(msg.sender, amt);
        emit Stake(amt, msg.sender);
        emit BalanceUpdated(address(this), stakeAsset, IERC20(stakeAsset).balanceOf(address(this)));
    }

    function unstake(uint256 amt) external delegateLock {
        require(
            amt <= getUnstakeableBalance(msg.sender),
            "Stakelocker:ERR_AMT_REQUESTED_UNAVAILABLE"
        );
        updateFundsReceived();
        withdrawFunds(); //has to be before the transfer or they will end up here
        _transfer(msg.sender, address(this), amt);
        require(
            IERC20(stakeAsset).transferFrom(address(this), msg.sender, amt),
            "StakeLocker:ERR_STAKE_ASSET_BALANCE_DEPLETED"
        );
        _burn(address(this), amt);
        emit Unstake(amt, msg.sender);
        emit BalanceUpdated(address(this), stakeAsset, IERC20(stakeAsset).balanceOf(address(this)));
    }

    // TODO: Make sure LP gets the delete function implemented.
    function deleteLP() external isLP {
        isLPDefunct = true;
    }

    function finalizeLP() external isLP {
        isLPFinalized = true;
    }

    function withdrawETH(address payable dst) external isGovernor {
        dst.transfer(address(this).balance);
    }

    /** 
     * @notice updates data structure that stores the information used to calculate unstake delay
     * @param staker address of staker
     * @param amt amount he is staking
     */
    function _updateStakeDate(address staker, uint256 amt) internal {
        if (stakeDate[staker] == 0) {
            stakeDate[staker] = block.timestamp;
        } else {
            uint256 date = stakeDate[staker];
            // Make sure this is executed before mint or line below needs change on denominator
            uint256 coef = (WAD * amt) / (balanceOf(staker) + amt); // Yes, i want 0 if amt is too small
            // This addition will start to overflow in about 3^52 years
            stakeDate[staker] = (date * WAD + (block.timestamp - date) * coef) / WAD;
            // I know this is insane but its good trust me
        }
    }

    /**
     * @dev view function returning your unstakeable balance.
     * @param staker wallet address
     * @return uint amount of BPTs that may be unstaked
     */
    function getUnstakeableBalance(address staker) public view returns (uint256) {
        uint256 bal = balanceOf(staker);
        uint256 time = (block.timestamp - stakeDate[staker]) * WAD;
        uint256 out = ((time / (IGlobals(globals).unstakeDelay() + 1)) * bal) / WAD;
        // The plus one is to avoid division by 0 if unstakeDelay is 0, creating 1 second inaccuracy
        // Also i do indeed want this to return 0 if denominator is less than WAD
        if (out > bal) {
            out = bal;
        }
        return out;
    }

    // TODO: Make this handle transfer of time lock more properly, parameterize _updateStakeDate
    //      to these ends to save code.
    //      can improve this so the updated age of tokens reflects their age in the senders wallets
    //      right now it simply is equivalent to the age update if the receiver was making a new stake.
    function _transfer(address from, address to, uint256 amt) internal override delegateLock {
        super._transfer(from, to, amt);
        _updateStakeDate(to, amt);
    }

    /**
     * @notice Withdraws all available funds for a token holder
     */
    function withdrawFunds() public override {
        // Must be public so it can be called insdie here
        uint256 withdrawableFunds = _prepareWithdraw();
        require(
            fundsToken.transfer(msg.sender, withdrawableFunds),
            "FDT_ERC20Extension.withdrawFunds: TRANSFER_FAILED"
        );

        _updateFundsTokenBalance();
    }

    /**
     * @dev Updates the current funds token balance
     * and returns the difference of new and previous funds token balances
     * @return A int256 representing the difference of the new and previous funds token balance
     */
    function _updateFundsTokenBalance() internal returns (int256) {
        uint256 prevFundsTokenBalance = fundsTokenBalance;

        fundsTokenBalance = fundsToken.balanceOf(address(this));

        return int256(fundsTokenBalance).sub(int256(prevFundsTokenBalance));
    }

    /**
     * @notice Register a payment of funds in tokens. May be called directly after a deposit is made.
     * @dev Calls _updateFundsTokenBalance(), whereby the contract computes the delta of the previous and the new
     * funds token balance and increments the total received funds (cumulative) by delta by calling _registerFunds()
     */
    function updateFundsReceived() public {
        int256 newFunds = _updateFundsTokenBalance();

        if (newFunds > 0) {
            _distributeFunds(newFunds.toUint256Safe());
        }
    }
}
