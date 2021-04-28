// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "./BasicFDT.sol";

/// @title ExtendedFDT implements FDT functionality for accounting for losses
abstract contract ExtendedFDT is BasicFDT {
    using SafeMath       for uint256;
    using SafeMathUint   for uint256;
    using SignedSafeMath for  int256;
    using SafeMathInt    for  int256;

    uint256 internal lossesPerShare;

    mapping(address => int256)  internal lossesCorrection;
    mapping(address => uint256) internal recognizedLosses;

    event   LossesPerShareUpdated(uint256 lossesPerShare);
    event LossesCorrectionUpdated(address indexed account, int256 lossesCorrection);

    /**
        @dev   This event emits when new losses are distributed.
        @param by                The address of the sender who distributed losses.
        @param lossesDistributed The amount of losses received for distribution.
    */
    event LossesDistributed(address indexed by, uint256 lossesDistributed);

    /**
        @dev   This event emits when distributed losses are recognized by a token holder.
        @param by                    The address of the receiver of losses.
        @param lossesRecognized      The amount of losses that were recognized.
        @param totalLossesRecognized The total amount of losses that were recognized.
    */
    event LossesRecognized(address indexed by, uint256 lossesRecognized, uint256 totalLossesRecognized);

    constructor(string memory name, string memory symbol) BasicFDT(name, symbol) public { }

    /**
        @dev Distributes losses to token holders.
        @dev It reverts if the total supply of tokens is 0.
        @dev It emits a `LossesDistributed` event if the amount of received losses is greater than 0.
        @dev It emits a `LossesPerShareUpdated` event if the amount of received losses is greater than 0.
             About undistributed losses:
                In each distribution, there is a small amount of losses which does not get distributed,
                which is `(value * pointsMultiplier) % totalSupply()`.
             With a well-chosen `pointsMultiplier`, the amount losses that are not getting distributed
                in a distribution can be less than 1 (base unit).
             We can actually keep track of the undistributed losses in a distribution
                and try to distribute it in the next distribution
    */
    function _distributeLosses(uint256 value) internal {
        require(totalSupply() > 0, "FDT:ZERO_SUPPLY");

        if (value == 0) return;

        uint256 _lossesPerShare = lossesPerShare.add(value.mul(pointsMultiplier) / totalSupply());
        lossesPerShare          = _lossesPerShare;

        emit LossesDistributed(msg.sender, value);
        emit LossesPerShareUpdated(_lossesPerShare);
    }

    /**
        @dev    Prepares losses withdrawal.
        @dev    It emits a `LossesWithdrawn` event if the amount of withdrawn losses is greater than 0.
        @return recognizableDividend The amount of dividend losses that can be recognized.
    */
    function _prepareLossesWithdraw() internal returns (uint256 recognizableDividend) {
        recognizableDividend = recognizableLossesOf(msg.sender);

        uint256 _recognizedLosses    = recognizedLosses[msg.sender].add(recognizableDividend);
        recognizedLosses[msg.sender] = _recognizedLosses;

        emit LossesRecognized(msg.sender, recognizableDividend, _recognizedLosses);
    }

    /**
        @dev    View the amount of losses that an address can withdraw.
        @param  _owner The address of a token holder.
        @return The amount of losses that `_owner` can withdraw.
    */
    function recognizableLossesOf(address _owner) public view returns (uint256) {
        return accumulativeLossesOf(_owner).sub(recognizedLosses[_owner]);
    }

    /**
        @dev    View the amount of losses that an address has recognized.
        @param  _owner The address of a token holder
        @return The amount of losses that `_owner` has recognized
    */
    function recognizedLossesOf(address _owner) external view returns (uint256) {
        return recognizedLosses[_owner];
    }

    /**
        @dev    View the amount of losses that an address has earned in total.
        @dev    accumulativeLossesOf(_owner) = recognizableLossesOf(_owner) + recognizedLossesOf(_owner)
                = (lossesPerShare * balanceOf(_owner) + lossesCorrection[_owner]) / pointsMultiplier
        @param  _owner The address of a token holder
        @return The amount of losses that `_owner` has earned in total
    */
    function accumulativeLossesOf(address _owner) public view returns (uint256) {
        return
            lossesPerShare
                .mul(balanceOf(_owner))
                .toInt256Safe()
                .add(lossesCorrection[_owner])
                .toUint256Safe() / pointsMultiplier;
    }

    /**
        @dev   Internal function that transfer tokens from one address to another. Update pointsCorrection to keep funds unchanged.
        @dev         It emits a `LossesCorrectionUpdated` event for the sender and receiver.
        @param from  The address to transfer from
        @param to    The address to transfer to
        @param value The amount to be transferred
    */
    function _transfer(
        address from,
        address to,
        uint256 value
    ) internal virtual override {
        super._transfer(from, to, value);

        int256 _lossesCorrection    = lossesPerShare.mul(value).toInt256Safe();
        int256 lossesCorrectionFrom = lossesCorrection[from].add(_lossesCorrection);
        lossesCorrection[from]      = lossesCorrectionFrom;
        int256 lossesCorrectionTo   = lossesCorrection[to].sub(_lossesCorrection);
        lossesCorrection[to]        = lossesCorrectionTo;

        emit LossesCorrectionUpdated(from, lossesCorrectionFrom);
        emit LossesCorrectionUpdated(to,   lossesCorrectionTo);
    }

    /**
        @dev   Internal function that mints tokens to an account. Update lossesCorrection to keep losses unchanged.
        @dev   It emits a `LossesCorrectionUpdated` event.
        @param account The account that will receive the created tokens.
        @param value   The amount that will be created.
    */
    function _mint(address account, uint256 value) internal virtual override {
        super._mint(account, value);

        int256 _lossesCorrection = lossesCorrection[account].sub(
            (lossesPerShare.mul(value)).toInt256Safe()
        );

        lossesCorrection[account] = _lossesCorrection;

        emit LossesCorrectionUpdated(account, _lossesCorrection);
    }

    /**
        @dev   Internal function that burns an amount of the token of a given account. Update lossesCorrection to keep losses unchanged.
        @dev   It emits a `LossesCorrectionUpdated` event.
        @param account The account whose tokens will be burnt.
        @param value   The amount that will be burnt.
    */
    function _burn(address account, uint256 value) internal virtual override {
        super._burn(account, value);

        int256 _lossesCorrection = lossesCorrection[account].add(
            (lossesPerShare.mul(value)).toInt256Safe()
        );

        lossesCorrection[account] = _lossesCorrection;

        emit LossesCorrectionUpdated(account, _lossesCorrection);
    }

    /**
        @dev Register a loss. May be called directly after a shortfall after BPT burning occurs.
        @dev Calls _updateLossesTokenBalance(), whereby the contract computes the delta of the new and the previous
             losses and increments the total losses (cumulative) by delta by calling _distributeLosses()
    */
    function updateLossesReceived() public virtual {
        int256 newLosses = _updateLossesBalance();

        if (newLosses <= 0) return;

        _distributeLosses(newLosses.toUint256Safe());
    }

    /**
        @dev Recognizes all recognizable losses for a user using loss accounting.
    */
    function _recognizeLosses() internal virtual returns (uint256 losses) { }

    /**
        @dev    Updates the current losses balance and returns the difference of new and previous losses balances.
        @return A int256 representing the difference of the new and previous losses balance.
    */
    function _updateLossesBalance() internal virtual returns (int256) { }
}
