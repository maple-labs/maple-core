// SPDX-License-Identifier: MIT

pragma solidity 0.7.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./Token/IFundsDistributionToken.sol";
import "./Token/FundsDistributionToken.sol";
import "./interface/ILiquidityPool.sol";
import "./interface/IGlobals.sol";
import "hardhat/console.sol";

/// @title LPStakeLocker is responsbile for escrowing staked assets and distributing a portion of interest payments.
contract LPStakeLocker is IFundsDistributionToken, FundsDistributionToken {
    
    using SafeMathInt for int256;
    using SignedSafeMath for int256;

    //map address to date value
    mapping(address => uint256) private stakeDate;

    // The primary investment asset for the LP, and the dividend token for this contract.
    IERC20 private ILiquidAsset;
    IERC20 private IStakedAsset;
    // @notice  The amount of LiquidAsset tokens (dividends) currently present and accounted for in this contract.
    uint256 public fundsTokenBalance;

    // @notice The primary investment asset for the liquidity pool. Also the dividend token for this contract.
    address public liquidAsset;

    bool private isLPDefunct;
    bool private isLPFinalized;
    // @notice The asset deposited by stakers into this contract, for liquidation during defaults.
    address public stakedAsset;
    IGlobals private IMapleGlobals;
    ILiquidityPool private IParentLP;

    //scaling factor for synthetic float division
    uint256 constant _ONE = 10**18;

    // @notice parent liquidity pool
    address public immutable parentLP; //TODO: not strictly needed, redundant to IParentLP 

    // TODO: Dynamically assign name and locker to the FundsDistributionToken() params.
    constructor(
        address _stakedAsset,
        address _liquidAsset,
        address _parentLP,
        address _globals
    ) public FundsDistributionToken("Maple Stake Locker", "MPLSTAKE") {
        liquidAsset = _liquidAsset;
        stakedAsset = _stakedAsset;
        parentLP = _parentLP;
        IParentLP = ILiquidityPool(_parentLP);
        ILiquidAsset = IERC20(_liquidAsset);
        IStakedAsset = IERC20(_stakedAsset);
        IMapleGlobals = IGlobals(_globals);
    }

    modifier delegateLock() {
        require(
            msg.sender != IParentLP.poolDelegate() || isLPDefunct || !isLPFinalized,
            "LPStakeLocker:ERR DELEGATE STAKE LOCKED"
        );
        _;
    }
    modifier isLP() { //TODO: fucked up things were happening here and mysterious dissapeared when the console.log was added
	console.log("msg.sender",msg.sender==parentLP);
        require(msg.sender==parentLP, "LPStakeLocker:ERR UNAUTHORIZED");
        _;
    }

    /**
     * @notice Deposit stakedAsset and mint an equal number of FundsDistributionTokens to the user
     * @param _amt Amount of stakedAsset(BPTs) to stake
     */
    function stake(uint256 _amt) external {
        require(
            IStakedAsset.transferFrom(msg.sender, address(this), _amt),
            "LPStakeLocker: ERR_INSUFFICIENT_APPROVED_FUNDS"
        );
        _updateStakeDate(msg.sender, _amt);
        _mint(msg.sender, _amt);
    }

    function unstake(uint256 _amt) external delegateLock {
        require(
            _amt <= getUnstakeableBalance(msg.sender),
            "LPStakelocker: not enough unstakeable balance"
        );
        updateFundsReceived();
        withdrawFunds(); //has to be before the transfer or they will end up here
        _transfer(msg.sender, address(this), _amt);
        require(
            IStakedAsset.transferFrom(address(this), msg.sender, _amt),
            "LPStakeLocker: ERR I DONT HAVE YOUR BPTs"
        );
        _burn(address(this), _amt);
    }

    /**
     * @notice Withdraws all available funds for a token holder
     */
    function withdrawFunds() public override {
        //must be public so it can be called insdie here
        uint256 withdrawableFunds = _prepareWithdraw();
        require(
            ILiquidAsset.transfer(msg.sender, withdrawableFunds),
            "FDT_ERC20Extension.withdrawFunds: TRANSFER_FAILED"
        );

        _updateFundsTokenBalance();
    }

    function deleteLP() external isLP {
        isLPDefunct = true;
    }//TODO: make sure LP gets the delete function implemented

    function finalizeLP() external isLP {
        isLPFinalized = true;
    }

    /** @notice updates data structure that stores the information used to calculate unstake delay
     * @param _addy address of staker
     * @param _amt ammount he is staking
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
     * @return uint ammount of BPTs that may be unstaked
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

    /**
     * @dev Updates the current funds token balance
     * and returns the difference of new and previous funds token balances
     * @return A int256 representing the difference of the new and previous funds token balance
     */
    function _updateFundsTokenBalance() internal returns (int256) {
        uint256 prevFundsTokenBalance = fundsTokenBalance;

        fundsTokenBalance = ILiquidAsset.balanceOf(address(this));

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

    function _transfer(
        address from,
        address to,
        uint256 value
    ) internal override delegateLock {
        super._transfer(from, to, value);
        _updateStakeDate(to, value);
	//TODO: make this handle transfer of time lock more properly, parameterize _updateStakeDate 
	// to these ends to save code. 
        //can improve this so the updated age of tokens reflects their age in the senders wallets
        //right now it simply is equivalent to the age update if the receiver was making a new stake
    }
}
