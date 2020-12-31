// SPDX-License-Identifier: MIT

pragma solidity >=0.6.11;

import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "./token/IFundsDistributionToken.sol";
import "./token/FundsDistributionToken.sol";
import "./interfaces/ILiquidityPool.sol";
import "./interfaces/IGlobals.sol";

/// @title StakeLocker is responsbile for escrowing staked assets and distributing a portion of interest payments.
contract StakeLocker is IFundsDistributionToken, FundsDistributionToken {
    using SafeMathInt for int256;
    using SignedSafeMath for int256;

    //map address to date value
    mapping(address => uint256) private stakeDate; // Consider making public

    // The primary investment asset for the LP, and the dividend token for this contract.
    IERC20 private ILiquidityAsset;
    IERC20 private IStakeAsset;
    IERC20 private fundsToken;

    /// @notice  The amount of LiquidityAsset tokens (dividends) currently present and accounted for in this contract.
    uint256 public fundsTokenBalance;

    /// @notice The LiquidityAsset for the LiquidityPool as well as the dividend token for this contract.
    address public liquidityAsset;

    bool private isLPDefunct;
    bool private isLPFinalized;

    /// @notice The asset deposited by stakers into this contract, for liquidation during defaults.
    address public stakeAsset;

    // Interface for the MapleGlobals.sol contract.
    IGlobals private IMapleGlobals;

    // Interface for the parent/owner of this contract, a liquidity pool.
    ILiquidityPool private IParentLP;

    //scaling factor for synthetic float division
    uint256 constant _ONE = 10**18;

    // TODO: Consider if this variable is needed, redundant to IParentLP.
    /// @notice The parent liquidity pool.
    address public immutable parentLP;

    event BalanceUpdated(address who, address token, uint256 balance);

    // TODO: Dynamically assign name and locker to the FundsDistributionToken() params.
    constructor(
        address _stakeAsset,
        address _liquidityAsset,
        address _parentLP,
        address _globals
    ) FundsDistributionToken("Maple Stake Locker", "MPLSTAKE") public {
        liquidityAsset = _liquidityAsset;
        stakeAsset = _stakeAsset;
        parentLP = _parentLP;
        IParentLP = ILiquidityPool(_parentLP);
        ILiquidityAsset = IERC20(_liquidityAsset);
        fundsToken = ILiquidityAsset;
        IStakeAsset = IERC20(_stakeAsset);
        IMapleGlobals = IGlobals(_globals);
    }

    event Stake(uint256 _amount, address _staker);
    event Unstake(uint256 _amount, address _staker);

    modifier delegateLock() {
        require(
            msg.sender != IParentLP.poolDelegate() || isLPDefunct || !isLPFinalized,
            "StakeLocker:ERR_DELEGATE_STAKE_LOCKED"
        );
        _;
    }

    //TODO: Identify why an error is thrown when console.log() is not present in this modifier.
    modifier isLP() {
        require(msg.sender == parentLP, "StakeLocker:ERR_UNAUTHORIZED");
        _;
    }
    modifier isGovernor() {
        require(msg.sender == IMapleGlobals.governor(), "msg.sender is not Governor");
        _;
    }

    /**
     * @notice Deposit stakeAsset and mint an equal number of FundsDistributionTokens to the user
     * @param _amt Amount of stakeAsset(BPTs) to stake
     */
    function stake(uint256 _amt) external {
        require(
            IStakeAsset.transferFrom(msg.sender, address(this), _amt),
            "StakeLocker:ERR_INSUFFICIENT_APPROVED_FUNDS"
        );
        _updateStakeDate(msg.sender, _amt);
        _mint(msg.sender, _amt);
        emit Stake(_amt, msg.sender);
        emit BalanceUpdated(address(this), address(IStakeAsset), IStakeAsset.balanceOf(address(this)));
    }

    function unstake(uint256 _amt) external delegateLock {
        require(
            _amt <= getUnstakeableBalance(msg.sender),
            "Stakelocker:ERR_AMT_REQUESTED_UNAVAILABLE"
        );
        updateFundsReceived();
        withdrawFunds(); //has to be before the transfer or they will end up here
        _transfer(msg.sender, address(this), _amt);
        require(
            IStakeAsset.transferFrom(address(this), msg.sender, _amt),
            "StakeLocker:ERR_STAKE_ASSET_BALANCE_DEPLETED"
        );
        _burn(address(this), _amt);
        emit Unstake(_amt, msg.sender);
        emit BalanceUpdated(address(this), address(IStakeAsset), IStakeAsset.balanceOf(address(this)));
    }

    //TODO: Make sure LP gets the delete function implemented.
    function deleteLP() external isLP {
        isLPDefunct = true;
    }

    function finalizeLP() external isLP {
        isLPFinalized = true;
    }

    function withdrawETH(address payable _to) external isGovernor {
        _to.transfer(address(this).balance);
    }

    /** @notice updates data structure that stores the information used to calculate unstake delay
     * @param _addy address of staker
     * @param _amt amount he is staking
     */
    function _updateStakeDate(address _addy, uint256 _amt) internal {
        if (stakeDate[_addy] == 0) {
            stakeDate[_addy] = block.timestamp;
        } else {
            uint256 _date = stakeDate[_addy];
            //make sure this is executed before mint or line below needs change on denominator
            uint256 _coef = (_ONE * _amt) / (balanceOf(_addy) + _amt); //yes, i want 0 if _amt is too small
            //thhis addition will start to overflow in about 3^52 years
            stakeDate[_addy] = (_date * _ONE + (block.timestamp - _date) * _coef) / _ONE;
            //I know this is insane but its good trust me
        }
    }

    /**
     * @dev view function returning your unstakeable balance.
     * @param _addy wallet address
     * @return uint amount of BPTs that may be unstaked
     */
    function getUnstakeableBalance(address _addy) public view returns (uint256) {
        uint256 _bal = balanceOf(_addy);
        uint256 _time = (block.timestamp - stakeDate[_addy]) * _ONE;
        uint256 _out = ((_time / (IMapleGlobals.unstakeDelay() + 1)) * _bal) / _ONE;
        //the plus one is to avoid division by 0 if unstakeDelay is 0, creating 1 second inaccuracy
        //also i do indeed want this to return 0 if denominator is less than _ONE
        if (_out > _bal) {
            _out = _bal;
        }
        return _out;
    }

    // TODO: Make this handle transfer of time lock more properly, parameterize _updateStakeDate
    //      to these ends to save code.
    //      can improve this so the updated age of tokens reflects their age in the senders wallets
    //      right now it simply is equivalent to the age update if the receiver was making a new stake.
    function _transfer(
        address from,
        address to,
        uint256 value
    ) internal override delegateLock {
        super._transfer(from, to, value);
        _updateStakeDate(to, value);
    }

    /**
     * @notice Withdraws all available funds for a token holder
     */
    function withdrawFunds() public /* override */ {
        //must be public so it can be called insdie here
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
