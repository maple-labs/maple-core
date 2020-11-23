// SPDX-License-Identifier: MIT

pragma solidity 0.7.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./Token/IFundsDistributionToken.sol";
import "./Token/FundsDistributionToken.sol";
import "./interface/IGlobals.sol";
import "./interface/IFundingLocker.sol";
import "./interface/IFundingLockerFactory.sol";
import "./interface/ICollateralLockerFactory.sol";

/// @title LoanVault is the core loan vault contract.
contract LoanVault is IFundsDistributionToken, FundsDistributionToken {

    using SafeMathInt for int256;
    using SignedSafeMath for int256;
    using SafeMath for uint256;

    // The fundsToken (dividends) and assetRequested.
    IERC20 private fundsToken;

    // The fundsToken (dividends) and assetRequested.
    IERC20 private IRequestedAsset;

    // The collateral asset for this loan vault.
    IERC20 private ICollateralAsset;

    // The maple globals contract.
    IGlobals private MapleGlobals;

    /// @notice The amount of fundsToken (assetRequested) currently present and accounted for in this contract.
    uint256 public fundsTokenBalance;

    /// @notice The asset deposited by lenders into the InvestmentLocker, when funding this loan.
    address public assetRequested;

    /// @notice The asset deposited by borrower into the CollateralLocker, for collateralizing this loan.
    address public assetCollateral;

    /// @notice The FundingLocker for this contract.
    address public fundingLocker;
    address public fundingLockerFactory;

    /// @notice The CollateralLocker for this contract.
    address public collateralLocker;
    address public collateralLockerFactory;

    /// @notice The borrower of this loan, responsible for repayments.
    address public borrower;

    /// @notice The loan specifications.
    uint public aprBips;
    uint public numberOfPayments;
    uint public paymentIntervalSeconds;
    uint public minRaise;
    uint public desiredRaise;
    uint public collateralAtDesiredRaise;
    
    /// @notice The repayment calculator for this loan.
    address public repaymentCalculator;

    /// @notice The premium calculator for this loan.
    address public premiumCalculator;
    
    /// @notice The current state of this loan, as defined in the State enum below.
    State public loanState;

    enum State { Initialized, Funding, Active, Defaulted, Matured }

    modifier isState(State _state) {
        require(loanState == _state, "LoanVault::FAIL_STATE_CHECK");
        _;
    }

    modifier isBorrower() {
        require(msg.sender == borrower, "LoanVault::MSG_SENDER_NOT_BORROWER");
        _;
    }

    /// @notice Constructor for loan vault.
    /// @param _assetRequested The asset borrower is requesting funding in.
    /// @param _assetCollateral The asset provided as collateral by the borrower.
    /// @param _fundingLockerFactory Factory to instantiate FundingLocker through.
    /// @param _collateralLockerFactory Factory to instantiate CollateralLocker through.
    /// @param name The name of the loan vault's token (minted when investors fund the loan).
    /// @param symbol The ticker of the loan vault's token.
    /// @param _mapleGlobals Address of the MapleGlobals.sol contract.
    constructor(
        address _assetRequested,
        address _assetCollateral,
        address _fundingLockerFactory,
        address _collateralLockerFactory,
        string memory name,
        string memory symbol,
        address _mapleGlobals
    ) FundsDistributionToken(name, symbol) {

        require(
            address(_assetRequested) != address(0),
            "FDT_ERC20Extension: INVALID_FUNDS_TOKEN_ADDRESS"
        );

        assetRequested = _assetRequested;
        assetCollateral = _assetCollateral;
        fundingLockerFactory = _fundingLockerFactory;
        collateralLockerFactory = _collateralLockerFactory;
        IRequestedAsset = IERC20(_assetRequested);
        MapleGlobals = IGlobals(_mapleGlobals);
        fundsToken = IRequestedAsset;
        borrower = tx.origin;

    }

    /// @notice Provide the specifications of the loan, transition state from Initialized to Funding.
    /// @param _details The specifications of the loan.
    ///        _details[0] = APR_BIPS
    ///        _details[1] = NUMBER_OF_PAYMENTS
    ///        _details[2] = PAYMENT_INTERVAL_SECONDS
    ///        _details[3] = MIN_RAISE
    ///        _details[4] = DESIRED_RAISE
    ///        _details[5] = COLLATERAL_AT_DESIRED_RAISE
    /// @param _repaymentCalculator The calculator used for interest and principal repayment calculations.
    /// @param _premiumCalculator The calculator used for call premiums.
    function prepareLoan(
        uint[6] memory _details,
        address _repaymentCalculator,
        address _premiumCalculator
    ) external isState(State.Initialized) isBorrower {

        // Transition state first.
        loanState = State.Funding;

        // Perform validity cross-checks.
        require(
            _details[1] >= 1, 
            "LoanVault::prepareLoan:ERR_NUMBER_OF_PAYMENTS_LESS_THAN_1"
        );
        require(
            MapleGlobals.validPaymentIntervalSeconds(_details[2]), 
            "LoanVault::prepareLoan:ERR_INVALID_PAYMENT_INTERVAL_SECONDS"
        );
        require(_details[4] >= _details[3] && _details[3] > 0,
            "LoanVault::prepareLoan:ERR_MIN_RAISE_ABOVE_DESIRED_RAISE_OR_MIN_RAISE_EQUALS_ZERO"
        );
        require(
            MapleGlobals.validRepaymentCalculators(_repaymentCalculator), 
            "LoanVault::prepareLoan:ERR_INVALID_REPAYMENT_CALCULATOR"
        );
        require(
            MapleGlobals.validPremiumCalculators(_premiumCalculator), 
            "LoanVault::prepareLoan:ERR_INVALID_PREMIUM_CALCULATOR"
        );

        // Update state variables.
        aprBips = _details[0];
        numberOfPayments = _details[1];
        paymentIntervalSeconds = _details[2];
        minRaise = _details[3];
        desiredRaise = _details[4];
        collateralAtDesiredRaise = _details[5];
        repaymentCalculator = _repaymentCalculator;
        premiumCalculator = _premiumCalculator;

        // Deploy a funding locker.
        fundingLocker = IFundingLockerFactory(fundingLockerFactory).newLocker(assetRequested);
    }

    /**
     * @notice Fund this loan and mint the investor LoanTokens.
     * @param _amount Amount of _assetRequested to fund the loan for.
     */
    // TODO: Implement and test this function.
    function fundLoan(uint _amount) external isState(State.Funding) {
        // TODO: Consider decimal precision difference: RequestedAsset <> FundsToken
        require(
            IRequestedAsset.transferFrom(tx.origin, address(this), _amount),
            "LoanVault::fundLoan:ERR_INSUFFICIENT_APPROVED_FUNDS"
        );
        require(
            IRequestedAsset.transfer(fundingLocker, _amount), 
            "LoanVault::fundLoan:ERR_TRANSFER_FUNDS"
        );
        _mint(tx.origin, _amount);
    }

    /// @notice End funding period by claiming funds, posting collateral, transitioning loanState from Funding to Active.
    /// @param _drawdownAmount Amount of fundingAsset borrower will claim, remainder is returned to LoanVault.
    // TODO: Implement and test this function.
    function endFunding(uint _drawdownAmount) external isState(State.Funding) isBorrower {

        require(
            _drawdownAmount >= minRaise, 
            "LoanVault::endFunding::ERR_DRAWDOWN_AMOUNT_BELOW_MIN_RAISE"
        );
        require(
            _drawdownAmount <= IRequestedAsset.balanceOf(fundingLocker), 
            "LoanVault::endFunding::ERR_DRAWDOWN_AMOUNT_ABOVE_FUNDING_LOCKER_BALANCE"
        );

        loanState = State.Active;

        // Instantiate collateral locker, fetch deposit required, transfer collateral from borrower to locker.
        collateralLocker = ICollateralLockerFactory(collateralLockerFactory).newLocker(assetCollateral);
        uint collateralAmountToPost = collateralRequiredForDrawdown(_drawdownAmount);
        require(
            ICollateralAsset.transferFrom(borrower, collateralLocker, collateralAmountToPost), 
            "LoanVault::endFunding:ERR_COLLATERAL_TRANSFER_FROM_APPROVAL_OR_BALANCE"
        );

        // Transfer funding amount from FundingLocker to Borrower, then remaining funds to LoanVault.
        require(
            IFundingLocker(fundingLocker).pull(borrower, _drawdownAmount), 
            "LoanVault::endFunding:CRITICAL_ERR_PULL"
        );
        require(
            IFundingLocker(fundingLocker).drain(),
            "LoanVault::endFunding:ERR_DRAIN"
        );
    }

    /// @notice Viewer helper for calculating collateral required to drawdown funding.
    /// @param _drawdownAmount The amount of fundingAsset to drawdown from FundingLocker.
    /// @return The amount of collateralAsset required to post for given _amount.
    function collateralRequiredForDrawdown(uint _drawdownAmount) internal view returns(uint) {
        return _drawdownAmount.mul(collateralAtDesiredRaise).div(desiredRaise);
    }

    /**
     * @notice Withdraws all available funds for a token holder
     */
    function withdrawFunds() external override {
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
        uint256 _prevFundsTokenBalance = fundsTokenBalance;

        fundsTokenBalance = fundsToken.balanceOf(address(this));

        return int256(fundsTokenBalance).sub(int256(_prevFundsTokenBalance));
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
