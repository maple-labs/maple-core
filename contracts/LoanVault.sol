// SPDX-License-Identifier: MIT

pragma solidity >=0.6.11;

import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "./Token/IFundsDistributionToken.sol";
import "./Token/FundsDistributionToken.sol";
import "./interface/IGlobals.sol";
import "./interface/IFundingLocker.sol";
import "./interface/IFundingLockerFactory.sol";
import "./interface/ICollateralLocker.sol";
import "./interface/ICollateralLockerFactory.sol";
import "./interface/IERC20Details.sol";
import "./interface/IRepaymentCalculator.sol";
import "./interface/ILateFeeCalculator.sol";
import "./interface/IPremiumCalculator.sol";
import "hardhat/console.sol";

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
    uint256 public aprBips;
    uint256 public numberOfPayments;
    uint256 public termDays;
    uint256 public paymentIntervalSeconds;
    uint256 public minRaise;
    uint256 public collateralBipsRatio;
    uint256 public fundingPeriodSeconds;
    uint256 public loanCreatedTimestamp;

    /// @notice The principal owed (initially the drawdown amount).
    uint256 public principalOwed;

    // Accounting variables.
    uint256 public principalPaid;
    uint256 public interestPaid;

    /// @notice The amount the borrower drew down, historical reference for calculators.
    uint256 public drawdownAmount;

    // The repayment calculator for this loan.
    IRepaymentCalculator public repaymentCalculator;

    // The late fee calculator for this loan.
    ILateFeeCalculator public lateFeeCalculator;

    // The premium calculator for this loan.
    IPremiumCalculator public premiumCalculator;

    /// @notice The unix timestamp due date of next payment.
    uint256 public nextPaymentDue;

    /// @notice The current state of this loan, as defined in the State enum below.
    State public loanState;

    // Live = Created
    // Active = Drawndown
    enum State { Live, Active, Matured }

    modifier isState(State _state) {
        require(loanState == _state, "LoanVault::ERR_FAIL_STATE_CHECK");
        _;
    }

    modifier isBorrower() {
        require(msg.sender == borrower, "LoanVault::ERR_MSG_SENDER_NOT_BORROWER");
        _;
    }

    /// @notice Fired when user calls fundLoan()
    event LoanFunded(uint256 _amountFunded, address indexed _fundedBy);

    /// @notice Constructor for loan vault.
    /// @param _assetRequested The asset borrower is requesting funding in.
    /// @param _assetCollateral The asset provided as collateral by the borrower.
    /// @param _fundingLockerFactory Factory to instantiate FundingLocker through.
    /// @param _collateralLockerFactory Factory to instantiate CollateralLocker through.
    /// @param _mapleGlobals Address of the MapleGlobals.sol contract.
    /// @param _specifications The specifications of the loan.
    ///        _specifications[0] = APR_BIPS
    ///        _specifications[1] = TERM_DAYS
    ///        _specifications[2] = PAYMENT_INTERVAL_DAYS
    ///        _specifications[3] = MIN_RAISE
    ///        _specifications[4] = COLLATERAL_BIPS_RATIO
    ///        _specifications[5] = FUNDING_PERIOD_DAYS
    /// @param _calculators The calculators used for the loan.
    ///        _calculators[0] = Repayment Calculator
    ///        _calculators[1] = LateFee Calculator
    ///        _calculators[2] = Premium Calculator
    constructor(
        address _assetRequested,
        address _assetCollateral,
        address _fundingLockerFactory,
        address _collateralLockerFactory,
        address _mapleGlobals,
        uint256[6] memory _specifications,
        address[3] memory _calculators,
        string memory _tUUID
    )
        FundsDistributionToken(
            string(abi.encodePacked("Maple Loan Vault Token ", _tUUID)),
            string(abi.encodePacked("ML", _tUUID))
        )
        public
    {
        require(
            address(_assetRequested) != address(0),
            "LoanVault::constructor:ERR_INVALID_FUNDS_TOKEN_ADDRESS"
        );

        assetRequested = _assetRequested;
        assetCollateral = _assetCollateral;
        fundingLockerFactory = _fundingLockerFactory;
        collateralLockerFactory = _collateralLockerFactory;
        IRequestedAsset = IERC20(_assetRequested);
        ICollateralAsset = IERC20(_assetCollateral);
        MapleGlobals = IGlobals(_mapleGlobals);
        fundsToken = IRequestedAsset;
        borrower = tx.origin;
        loanCreatedTimestamp = block.timestamp;

        // Perform validity cross-checks.
        require(
            MapleGlobals.isValidBorrowToken(_assetRequested),
            "LoanVault::constructor:ERR_INVALID_ASSET_REQUESTED"
        );
        require(
            MapleGlobals.isValidCollateral(_assetCollateral),
            "LoanVault::constructor:ERR_INVALID_ASSET_REQUESTED"
        );
        require(
            _specifications[2] != 0,
            "LoanVault::constructor:ERR_PAYMENT_INTERVAL_DAYS_EQUALS_ZERO"
        );
        require(
            _specifications[1].mod(_specifications[2]) == 0,
            "LoanVault::constructor:ERR_INVALID_TERM_AND_PAYMENT_INTERVAL_DIVISION"
        );
        require(_specifications[3] > 0, "LoanVault::constructor:ERR_MIN_RAISE_EQUALS_ZERO");
        require(_specifications[5] > 0, "LoanVault::constructor:ERR_FUNDING_PERIOD_EQUALS_ZERO");

        // Update state variables.
        aprBips = _specifications[0];
        termDays = _specifications[1];
        numberOfPayments = _specifications[1].div(_specifications[2]);
        paymentIntervalSeconds = _specifications[2].mul(1 days);
        minRaise = _specifications[3];
        collateralBipsRatio = _specifications[4];
        fundingPeriodSeconds = _specifications[5].mul(1 days);
        repaymentCalculator = IRepaymentCalculator(_calculators[0]);
        lateFeeCalculator = ILateFeeCalculator(_calculators[1]);
        premiumCalculator = IPremiumCalculator(_calculators[2]);
        nextPaymentDue = loanCreatedTimestamp.add(paymentIntervalSeconds);

        // Deploy a funding locker.
        fundingLocker = IFundingLockerFactory(fundingLockerFactory).newLocker(assetRequested);
    }

    /**
     * @notice Fund this loan and mint LoanTokens.
     * @param _amount Amount of _assetRequested to fund the loan for.
     * @param _mintedTokenReceiver The address to mint LoanTokens for.
     */
    function fundLoan(uint256 _amount, address _mintedTokenReceiver) external isState(State.Live) {
        // TODO: Consider testing decimal precision difference: RequestedAsset <> FundsToken
        require(
            IRequestedAsset.transferFrom(msg.sender, fundingLocker, _amount),
            "LoanVault::fundLoan:ERR_INSUFFICIENT_APPROVED_FUNDS"
        );
        emit LoanFunded(_amount, _mintedTokenReceiver);
        _mint(_mintedTokenReceiver, _amount);
    }

    /// @notice Returns the balance of _requestedAsset in the FundingLocker.
    /// @return The balance of FundingLocker.
    function getFundingLockerBalance() view public returns(uint) {
        return IRequestedAsset.balanceOf(fundingLocker);
    }

    /// @notice Returns the balance of _collateralAsset in the CollateralLocker.
    /// @return The balance of CollateralLocker.
    function getCollateralLockerBalance() view public returns(uint) {
        return ICollateralAsset.balanceOf(collateralLocker);
    }

    /// @notice End funding period by claiming funds, posting collateral, transitioning loanState from Funding to Active.
    /// @param _drawdownAmount Amount of fundingAsset borrower will claim, remainder is returned to LoanVault.
    function drawdown(uint256 _drawdownAmount) external isState(State.Live) isBorrower {

        console.log('a');
        require(
            _drawdownAmount >= minRaise, 
            "LoanVault::endFunding::ERR_DRAWDOWN_AMOUNT_BELOW_MIN_RAISE"
        );
        require(
            _drawdownAmount <= IRequestedAsset.balanceOf(fundingLocker), 
            "LoanVault::endFunding::ERR_DRAWDOWN_AMOUNT_ABOVE_FUNDING_LOCKER_BALANCE"
        );

        // Update the principal owed and drawdown amount for this loan.
        principalOwed = _drawdownAmount;
        drawdownAmount = _drawdownAmount;

        loanState = State.Active;

        console.log('b');
        // Deploy a collateral locker.
        collateralLocker = ICollateralLockerFactory(collateralLockerFactory).newLocker(assetCollateral);

        console.log('c');
        // Transfer the required amount of collateral for drawdown from Borrower to CollateralLocker.
        console.log(collateralRequiredForDrawdown(_drawdownAmount));
        console.log(borrower);
        console.log(collateralLocker);
        console.log(ICollateralAsset.balanceOf(borrower));
        console.log(ICollateralAsset.allowance(borrower, collateralLocker));
        require(
            ICollateralAsset.transferFrom(borrower, collateralLocker, collateralRequiredForDrawdown(_drawdownAmount)), 
            "LoanVault::endFunding:ERR_COLLATERAL_TRANSFER_FROM_APPROVAL_OR_BALANCE"
        );

        console.log('d');
        // Transfer funding amount from FundingLocker to Borrower, then drain remaining funds to LoanVault.
        require(
            IFundingLocker(fundingLocker).pull(borrower, _drawdownAmount), 
            "LoanVault::endFunding:CRITICAL_ERR_PULL"
        );
        console.log('e');
        require(
            IFundingLocker(fundingLocker).drain(),
            "LoanVault::endFunding:ERR_DRAIN"
        );
        console.log('f');
    }

    /// @notice Make the next payment for this loan.
    function makePayment() public isState(State.Active) {
        if (block.timestamp <= nextPaymentDue) {

            (
                uint256 _paymentAmount,
                uint256 _principal,
                uint256 _interest
            ) = repaymentCalculator.getNextPayment(address(this));

            require(
                IRequestedAsset.transferFrom(msg.sender, address(this), _paymentAmount),
                "LoanVault::makePayment:ERR_LACK_APPROVAL_OR_BALANCE"
            );

            // Update internal accounting variables.
            principalOwed = principalOwed.sub(_principal);
            principalPaid = principalPaid.add(_principal);
            interestPaid = interestPaid.add(_interest);
            nextPaymentDue = nextPaymentDue.add(paymentIntervalSeconds);
            numberOfPayments--;
        }
        else if (block.timestamp <= nextPaymentDue.add(MapleGlobals.gracePeriod())) {
            (
                uint256 _paymentAmount,
                uint256 _principal,
                uint256 _interest
            ) = repaymentCalculator.getNextPayment(address(this));
            // TODO: Identify whether _principalExtra is needed for lateFee (if only interest needeD).
            (
                uint256 _paymentAmountExtra,
                uint256 _principalExtra,
                uint256 _interestExtra
            ) = lateFeeCalculator.getLateFee(address(this));

            require(
                IRequestedAsset.transferFrom(msg.sender, address(this), _paymentAmount.add(_paymentAmountExtra)),
                "LoanVault::makePayment:ERR_LACK_APPROVAL_OR_BALANCE"
            );

            // Update internal accounting variables.
            principalOwed = principalOwed.sub(_principal);
            principalPaid = principalPaid.add(_principal).add(_principalExtra);
            interestPaid = interestPaid.add(_interest).add(_interestExtra);
            nextPaymentDue = nextPaymentDue.add(paymentIntervalSeconds);
            numberOfPayments--;
        }
        else {
            // TODO: Trigger default, or other action as per business requirements.
        }

        // Handle final payment.
        // TODO: Identify any other variables worth resetting on final payment.
        if (numberOfPayments == 0) {
            loanState = State.Matured;
            ICollateralLocker(collateralLocker).pull(borrower, getCollateralLockerBalance());
        }
    }

    /// @notice Returns the next payment amounts.
    /// @return [0] = Principal + Interest, [1] = Principal, [2] = Interest, [3] Due By Timestamp
    function getNextPayment() public view returns(uint256, uint256, uint256, uint256) {
        (
            uint256 _total, 
            uint256 _principal,
            uint256 _interest
        ) = repaymentCalculator.getNextPayment(address(this));
        return (_total, _principal, _interest, nextPaymentDue);
    }

    /// @notice Makes the full payment for this loan, a.k.a. "calling" the loan.
    function makeFullPayment() public isState(State.Active) {
        (
            uint256 _total, 
            uint256 _principal,
            uint256 _interest
        ) = premiumCalculator.getPremiumPayment(address(this));

        require(
            IRequestedAsset.transferFrom(msg.sender, address(this), _total),
            "LoanVault::makeFullPayment:ERR_LACK_APPROVAL_OR_BALANCE"
        );

        loanState = State.Matured;

        // Update internal accounting variables.
        // TODO: Identify any other variables worth resetting on full payment.
        principalOwed = 0;
        numberOfPayments = 0;
        principalPaid = principalPaid.add(_principal);
        interestPaid = interestPaid.add(_interest);
    }

    /// @notice Returns the payment amount when paying off the loan early.
    /// @return [0] = Principal + Interest, [1] = Principal, [2] = Interest
    function getFullPayment() public view returns(uint256, uint256, uint256) {
        (
            uint256 _total, 
            uint256 _principal,
            uint256 _interest
        ) = premiumCalculator.getPremiumPayment(address(this));
        return (_total, _principal, _interest);
    }


    /// @notice Viewer helper for calculating collateral required to drawdown funding.
    /// @param _drawdownAmount The amount of fundingAsset to drawdown from FundingLocker.
    /// @return The amount of collateralAsset required to post for given _amount.
    function collateralRequiredForDrawdown(uint256 _drawdownAmount) public view returns(uint256) {

        // Fetch value of collateral and funding asset.
        uint256 requestPrice = MapleGlobals.getPrice(assetRequested);
        uint256 collateralPrice = MapleGlobals.getPrice(assetCollateral);

        /*
            Current values fed into ChainLink oracles (8 decimals, based on Kovan values)
            DAI_USD  == 100232161
            USDC_USD == 100232161
            WETH_USD == 59452607912
            WBTC_USD == 1895510185012

            requestPrice(DAI || USDC) = 100232161
            collateralPrice(wBTC) = 1895510185012
            collateralPrice(wETH) = 59452607912
        */

        uint256 collateralRequiredUSD = requestPrice.mul(_drawdownAmount).mul(collateralBipsRatio).div(10000);
        uint256 collateralRequiredWEI = collateralRequiredUSD.div(collateralPrice);
        uint256 collateralRequiredFIN = collateralRequiredWEI.div(10**(18 - IERC20Details(assetCollateral).decimals()));

        return collateralRequiredFIN;
    }

    /**
     * @notice Withdraws all available funds for a token holder
     */
    function withdrawFunds() external /* override */ {
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
