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
    uint256 public aprBips;
    uint256 public numberOfPayments;
    uint256 public termDays;
    uint256 public paymentIntervalSeconds;
    uint256 public minRaise;
    uint256 public collateralBipsRatio;
    uint256 public fundingPeriodSeconds;
    uint256 public loanCreatedTimestamp;

    /// @notice The repayment calculator for this loan.
    address public repaymentCalculator;

    /// @notice The premium calculator for this loan.
    address public premiumCalculator;

    /// @notice The current state of this loan, as defined in the State enum below.
    State public loanState;

    // Live = Created
    // Active = Drawndown
    enum State { Live, Active }

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
    /// @param _repaymentCalculator The calculator used for interest and principal repayment calculations.
    constructor(
        address _assetRequested,
        address _assetCollateral,
        address _fundingLockerFactory,
        address _collateralLockerFactory,
        address _mapleGlobals,
        uint256[6] memory _specifications,
        address _repaymentCalculator,
        string memory _tUUID
    )
        FundsDistributionToken(
            string(abi.encodePacked("Maple Loan Vault Token ", _tUUID)),
            string(abi.encodePacked("ML", _tUUID))
        )
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
        repaymentCalculator = _repaymentCalculator;

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
