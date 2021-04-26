// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "lib/openzeppelin-contracts/contracts/math/SafeMath.sol";
import "lib/openzeppelin-contracts/contracts/math/SignedSafeMath.sol";
import "./IFDT.sol";
import "../math/SafeMathUint.sol";
import "../math/SafeMathInt.sol";

/// @title BasicFDT implements base level FDT functionality for accounting for revenues
abstract contract BasicFDT is IFDT, ERC20 {
    using SafeMath       for uint256;
    using SafeMathUint   for uint256;
    using SignedSafeMath for  int256;
    using SafeMathInt    for  int256;

    uint256 internal constant pointsMultiplier = 2 ** 128;
    uint256 internal pointsPerShare;

    mapping(address => int256)  internal pointsCorrection;
    mapping(address => uint256) internal withdrawnFunds;

    event   PointsPerShareUpdated(uint256 pointsPerShare);
    event PointsCorrectionUpdated(address indexed account, int256 pointsCorrection);

    constructor(string memory name, string memory symbol) ERC20(name, symbol) public { }

    /**
        @dev Distributes funds to token holders.
        @dev It reverts if the total supply of tokens is 0.
        @dev It emits a `FundsDistributed` event if the amount of received ether is greater than 0.
        @dev It emits a `PointsPerShareUpdated` event if the amount of received ether is greater than 0.
             About undistributed funds:
                In each distribution, there is a small amount of funds which does not get distributed,
                   which is `(value  pointsMultiplier) % totalSupply()`.
                With a well-chosen `pointsMultiplier`, the amount funds that are not getting distributed
                   in a distribution can be less than 1 (base unit).
                We can actually keep track of the undistributed ether in a distribution
                   and try to distribute it in the next distribution.
    */
    function _distributeFunds(uint256 value) internal {
        require(totalSupply() > 0, "FDT:ZERO_SUPPLY");

        if (value == 0) return;

        pointsPerShare = pointsPerShare.add(value.mul(pointsMultiplier) / totalSupply());
        emit FundsDistributed(msg.sender, value);
        emit PointsPerShareUpdated(pointsPerShare);
    }

    /**
        @dev Prepares funds withdrawal
        @dev It emits a `FundsWithdrawn` event if the amount of withdrawn ether is greater than 0.
        @return withdrawableDividend The amount of diviend funds that can be withdrawn.
    */
    function _prepareWithdraw() internal returns (uint256 withdrawableDividend) {
        withdrawableDividend = withdrawableFundsOf(msg.sender);

        withdrawnFunds[msg.sender] = withdrawnFunds[msg.sender].add(withdrawableDividend);

        emit FundsWithdrawn(msg.sender, withdrawableDividend, withdrawnFunds[msg.sender]);
    }

    /**
        @dev View the amount of funds that an address can withdraw.
        @param _owner The address of a token holder.
        @return The amount funds that `_owner` can withdraw.
    */
    function withdrawableFundsOf(address _owner) public view override returns (uint256) {
        return accumulativeFundsOf(_owner).sub(withdrawnFunds[_owner]);
    }

    /**
        @dev View the amount of funds that an address has withdrawn.
        @param _owner The address of a token holder.
        @return The amount of funds that `_owner` has withdrawn.
    */
    function withdrawnFundsOf(address _owner) public view returns (uint256) {
        return withdrawnFunds[_owner];
    }

    /**
        @dev View the amount of funds that an address has earned in total.
        @dev accumulativeFundsOf(_owner) = withdrawableFundsOf(_owner) + withdrawnFundsOf(_owner)
        = (pointsPerShare * balanceOf(_owner) + pointsCorrection[_owner]) / pointsMultiplier
        @param _owner The address of a token holder.
        @return The amount of funds that `_owner` has earned in total.
    */
    function accumulativeFundsOf(address _owner) public view returns (uint256) {
        return
            pointsPerShare
                .mul(balanceOf(_owner))
                .toInt256Safe()
                .add(pointsCorrection[_owner])
                .toUint256Safe() / pointsMultiplier;
    }

    /**
        @dev Internal function that transfer tokens from one address to another. Update pointsCorrection to keep funds unchanged.
        @dev It emits a `PointsCorrectionUpdated` event for the sender and receiver.
        @param from  The address to transfer from.
        @param to    The address to transfer to.
        @param value The amount to be transferred.
    */
    function _transfer(
        address from,
        address to,
        uint256 value
    ) internal virtual override {
        super._transfer(from, to, value);

        int256 _magCorrection = pointsPerShare.mul(value).toInt256Safe();
        pointsCorrection[from] = pointsCorrection[from].add(_magCorrection);
        pointsCorrection[to] = pointsCorrection[to].sub(_magCorrection);

        emit PointsCorrectionUpdated(from, pointsCorrection[from]);
        emit PointsCorrectionUpdated(to,   pointsCorrection[to]);
    }

    /**
        @dev Internal function that mints tokens to an account. Update pointsCorrection to keep funds unchanged.
        @param account The account that will receive the created tokens.
        @param value   The amount that will be created.
    */
    function _mint(address account, uint256 value) internal virtual override {
        super._mint(account, value);

        pointsCorrection[account] = pointsCorrection[account].sub(
            (pointsPerShare.mul(value)).toInt256Safe()
        );

        emit PointsCorrectionUpdated(account, pointsCorrection[account]);
    }

    /**
        @dev Internal function that burns an amount of the token of a given account. Update pointsCorrection to keep funds unchanged.
        @dev It emits a `PointsCorrectionUpdated` event.
        @param account The account whose tokens will be burnt.
        @param value   The amount that will be burnt.
    */
    function _burn(address account, uint256 value) internal virtual override {
        super._burn(account, value);

        pointsCorrection[account] = pointsCorrection[account].add(
            (pointsPerShare.mul(value)).toInt256Safe()
        );
        emit PointsCorrectionUpdated(account, pointsCorrection[account]);
    }

    /**
        @dev Withdraws all available funds for a token holder.
    */
    function withdrawFunds() public virtual override {}

    /**
        @dev Updates the current funds token balance
             and returns the difference of new and previous funds token balances.
        @return A int256 representing the difference of the new and previous funds token balance
    */
    function _updateFundsTokenBalance() internal virtual returns (int256) {}

    /**
        @dev Register a payment of funds in tokens. May be called directly after a deposit is made.
        @dev Calls _updateFundsTokenBalance(), whereby the contract computes the delta of the new and the previous
        funds token balance and increments the total received funds (cumulative) by delta by calling _registerFunds()
    */
    function updateFundsReceived() public virtual {
        int256 newFunds = _updateFundsTokenBalance();

        if (newFunds <= 0) return;

        _distributeFunds(newFunds.toUint256Safe());
    }
}
