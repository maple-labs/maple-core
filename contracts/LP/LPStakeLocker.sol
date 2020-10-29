// SPDX-License-Identifier: MIT

pragma solidity 0.7.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../Token/IFundsDistributionToken.sol";
import "../Token/FundsDistributionToken.sol";

contract LPStakeLocker is IFundsDistributionToken, FundsDistributionToken {

    using SafeMathInt for int256;
	using SignedSafeMath for int256;

	// token in which the funds/dividends can be sent for the FundsDistributionToken
	IERC20 private IliquidAsset; //private if it doesnt need to be public to save gas 
	
	// balance of liquidToken that the FundsDistributionToken currently holds
	uint256 public liquidTokenBalance;

    //address poolDelegate; // TODO: consider if required
    address stakedAsset;
    address liquidAsset;
    constructor (
        address _stakedAsset,
		address _liquidAsset
    ) FundsDistributionToken('Maple Stake Locker', 'MPLSTAKE') {
        //require(address(_liquidToken) != address(0), "FDT_ERC20Extension: INVALID_FUNDS_TOKEN_ADDRESS");
		liquidAsset = _liquidAsset;
        stakedAsset = _stakedAsset;
		IliquidAsset = IERC20(_liquidAsset);
    }
/* //i think this makes no sense as there is no hook for a ERC20 receive. its not a thing in ERC20. no interaction comes here. its only in the liquidAsset Contract
	modifier onlyLiquidAsset () {
		require(msg.sender == address(liquidAsset), "FDT_ERC20Extension.onlyIliquidAsset: UNAUTHORIZED_SENDER");
		_;
	}




	/**
	 * @notice Withdraws all available funds for a token holder
	 */
	function withdrawFunds() 
		external override
	{
		uint256 withdrawableFunds = _prepareWithdraw();
		
		require(IliquidAsset.transfer(msg.sender, withdrawableFunds), "FDT_ERC20Extension.withdrawFunds: TRANSFER_FAILED");

		_updateIliquidAssetBalance();
	}

	/**
	 * @dev Updates the current funds token balance 
	 * and returns the difference of new and previous funds token balances
	 * @return A int256 representing the difference of the new and previous funds token balance
	 */
	function _updateIliquidAssetBalance() internal returns (int256) {
		uint256 prevIliquidAssetBalance = liquidTokenBalance;
		
		liquidTokenBalance = IliquidAsset.balanceOf(address(this));

		return int256(liquidTokenBalance).sub(int256(prevIliquidAssetBalance));
	}

	/**
	 * @notice Register a payment of funds in tokens. May be called directly after a deposit is made.
	 * @dev Calls _updateIliquidAssetBalance(), whereby the contract computes the delta of the previous and the new 
	 * funds token balance and increments the total received funds (cumulative) by delta by calling _registerFunds()
	 */
/*	function updateFundsReceived() external {
		int256 newFunds = _updateIliquidAssetBalance();

		if (newFunds > 0) {
			_distributeFunds(newFunds.toUint256Safe());
		}
	}
*/
    // TODO: implement
    // Staker deposits BPTs into the locker.
    function stake(uint _amountStakedAsset) external returns(uint) {
        return _amountStakedAsset;
    }
/*
    // TODO: implement
    // Staker withdraws BPTs from the locker.
    function unstake(uint _amountStakedAsset) external returns(uint) {
        return _amountStakedAsset;
    }

    // TODO: implement
    // ... what's this supposed to do ??
    function withdrawUnstaked(uint _amountUnstaked) external returns (uint) {
        return _amountUnstaked;
    }

    // TODO: implement
    // Staker withdraws interest from the locker (presumably requires ERC2222).
    function withdrawInterest() external returns (uint) {
        return 0;
    }
*/
}