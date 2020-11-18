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

    /// @notice The CollateralLocker for this contract.
    address public collateralLocker;

    /// @notice The borrower of this loan, responsible for repayments.
    address public borrower;

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
        IRequestedAsset = IERC20(_assetRequested);
        fundsToken = IRequestedAsset;
        MapleGlobals = IGlobals(_mapleGlobals);
        borrower = tx.origin;

        // _initializeFundingLocker(_fundingLockerFactory);
        // _initializeCollateralLocker(_collateralLockerFactory);

    }

    /**
     * @notice Initailize the FundingLocker for this contract.
     * @param _fundingLockerFactory The factory contract to initialize FundingLocker through.
     */
    function _initializeFundingLocker(address _fundingLockerFactory) public {
        address _fundingLocker = IFundingLockerFactory(_fundingLockerFactory).newLocker(assetRequested);
        fundingLocker = _fundingLocker;
    }

    /**
     * @notice Initailize the CollateralLocker for this contract.
     * @param _collateralLockerFactory The factory contract to initialize CollateralLocker through.
     */
    function _initializeCollateralLocker(address _collateralLockerFactory) private {
        address _collateralLocker = ICollateralLockerFactory(_collateralLockerFactory).newLocker(assetCollateral);
        collateralLocker = _collateralLocker;
    }

    /// @notice Prepare this loan for funding by transitioning loanState from Initialized to Funding.
    function prepareLoan() external isState(State.Initialized) isBorrower {
        loanState = State.Funding;
    }

    /// @notice End funding period by claiming funds and transitioning loanState from Funding to Active.
    /// @param _amount The amount of fundingAsset borrower will claim, remainder returned to lenders.
    function endFunding(uint _amount) external isState(State.Funding) isBorrower {
        loanState = State.Active;
        // TODO: Handle collateral deposit here.
        require(IFundingLocker(fundingLocker).pull(borrower, _amount), "LoanVault::endFunding:ERR_PULL");
        require(IFundingLocker(fundingLocker).drain(),"LoanVault::endFunding:ERR_DRAIN");
    }

    /**
     * @notice Fund this loan and mint the investor LoanTokens.
     * @param _amount Amount of _assetRequested to fund the loan for.
     */
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
