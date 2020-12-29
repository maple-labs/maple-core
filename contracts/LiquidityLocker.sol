// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;

import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "./interfaces/ILoanVault.sol";

contract LiquidityLocker {

    IERC20 private immutable ILiquidityAsset;

    /// @notice The asset which this LiquidityLocker will escrow.
    address public liquidityAsset;

    /// @notice The LiquidityPool that owns this LiquidityLocker, for authorization purposes.
    address public immutable ownerLP;

    // TODO: Consider checking if the _liquidityPool (owner) is a valid LiquidityPool via LPFactory.
    constructor(address _liquidityAsset, address _liquidityPool) public {
        liquidityAsset = _liquidityAsset;
        ownerLP = _liquidityPool;
        ILiquidityAsset = IERC20(_liquidityAsset);
    }
    
    modifier isOwner() {
        require(msg.sender == ownerLP, "LiquidityLocker:ERR_MSG_SENDER_NOT_OWNER");
        _;
    }

    /// @notice Transfer liquidityAsset from this contract to an external contract.
    /// @param _amt Amount to transfer liquidityAsset to.
    /// @param _to Address to send liquidityAsset to.
    /// @return true if transfer succeeds.
    function transfer(address _to, uint256 _amt) external isOwner returns (bool) {
        require(_to != address(0), "LiquidityLocker::transfer:ERR_TO_VALUE_IS_NULL_ADDRESS");
        return ILiquidityAsset.transfer(_to, _amt);
    }

    // TODO: Consider checking if _loanVault is valid via LoanVaultFactory.
    /// @notice Fund a particular loan using available LiquidityAsset.
    /// @param _loanVault The address of the LoanVault to fund.
    /// @param _amt The amount of LiquidityAsset to fund.
    function fundLoan(address _loanVault, address _loanTokenLocker, uint256 _amt) external isOwner {
        ILiquidityAsset.approve(_loanVault, _amt);
        ILoanVault(_loanVault).fundLoan(_amt, _loanTokenLocker);
    }
}
