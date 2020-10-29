pragma solidity ^0.7.0;

import "./Token/IFundsDistributionToken.sol";
import "./Token/FundsDistributionToken.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract LP is IFundsDistributionToken, FundsDistributionToken {

    using SafeMathInt for int256;
	using SignedSafeMath for int256;

	// token in which the funds/dividends can be sent for the FundsDistributionToken
	IERC20 public FundsToken;
	
	// balance of fundsToken that the FundsDistributionToken currently holds
	uint256 public fundsTokenBalance;

    // Instantiated during constructor()
    uint public stakerFeeBasisPoints;
    uint public ongoingFeeBasisPoints;
    address public investmentAsset;
    address public stakedAsset;
    address public stakedAssetLocker;
    address public poolDelegate;

    constructor (
        address _investmentAsset,
        address _stakedAsset,
        address _stakedAssetLockerFactory,
		string memory name, 
		string memory symbol,
		IERC20 _fundsToken
    ) public FundsDistributionToken(name, symbol) {
        require(address(_fundsToken) != address(0), "FDT_ERC20Extension: INVALID_FUNDS_TOKEN_ADDRESS");
        
        // deploy _investmentAssetLocker / _stakedAssetLocker / _stakedLiquidationStrategy here ??
        // assign PoolInvestorWhitelist inherently (singular contract) ... or deploy (factory) ??

        // ierc20
		FundsToken = _fundsToken;

        // uint
        // StakerFeeBasisPoints = _stakerFeeBasisPoints;
        // OngoingFeeBasisPoints = _ongoingFeeBasisPoints;

        // address
        investmentAsset = _investmentAsset;
        stakedAsset = _stakedAsset;

        // bool
        // PublicPool = _publicPool;
    }

	modifier onlyFundsToken () {
		require(msg.sender == address(FundsToken), "FDT_ERC20Extension.onlyFundsToken: UNAUTHORIZED_SENDER");
		_;
	}

	/**
	 * @notice Withdraws all available funds for a token holder
	 */
	function withdrawFunds() 
		external override
	{
		uint256 withdrawableFunds = _prepareWithdraw();
		
		require(FundsToken.transfer(msg.sender, withdrawableFunds), "FDT_ERC20Extension.withdrawFunds: TRANSFER_FAILED");

		_updateFundsTokenBalance();
	}

	/**
	 * @dev Updates the current funds token balance 
	 * and returns the difference of new and previous funds token balances
	 * @return A int256 representing the difference of the new and previous funds token balance
	 */
	function _updateFundsTokenBalance() internal returns (int256) {
		uint256 prevFundsTokenBalance = fundsTokenBalance;
		
		fundsTokenBalance = FundsToken.balanceOf(address(this));

		return int256(fundsTokenBalance).sub(int256(prevFundsTokenBalance));
	}

	/**
	 * @notice Register a payment of funds in tokens. May be called directly after a deposit is made.
	 * @dev Calls _updateFundsTokenBalance(), whereby the contract computes the delta of the previous and the new 
	 * funds token balance and increments the total received funds (cumulative) by delta by calling _registerFunds()
	 */
	function updateFundsReceived() external {
		int256 newFunds = _updateFundsTokenBalance();

		if (newFunds > 0) {
			_distributeFunds(newFunds.toUint256Safe());
		}
	}

}

interface StakedAssetLockerFactory_LP {
    function newLocker(address _stakedAsset) external returns(address);
}

interface StakedAssetLocker_LP {
    function stake(uint _amountStakedAsset) external returns(uint);
    function unstake(uint _amountStakedAsset) external returns(uint);
    function withdrawUnstaked(uint _amountUnstaked) external returns(uint);
    function withdrawInterest() external returns(uint);
}
