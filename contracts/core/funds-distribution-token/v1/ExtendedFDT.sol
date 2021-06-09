// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "./interfaces/IExtendedFDT.sol";

import "./BasicFDT.sol";

/// @title ExtendedFDT implements the FDT functionality for accounting for losses.
abstract contract ExtendedFDT is IExtendedFDT, BasicFDT {
    using SafeMath       for uint256;
    using SafeMathUint   for uint256;
    using SignedSafeMath for  int256;
    using SafeMathInt    for  int256;

    uint256 internal lossesPerShare;

    mapping(address => int256)  internal lossesCorrection;
    mapping(address => uint256) internal recognizedLosses;

    constructor(string memory name, string memory symbol) BasicFDT(name, symbol) public { }

    /**
        @dev Distributes losses to token holders.
        @dev It reverts if the total supply of tokens is 0.
        @dev It emits a `LossesDistributed` event if the amount of received losses is greater than 0.
        @dev It emits a `LossesPerShareUpdated` event if the amount of received losses is greater than 0.
             About undistributed losses:
                In each distribution, there is a small amount of losses which do not get distributed,
                which is `(value * pointsMultiplier) % totalSupply()`.
             With a well-chosen `pointsMultiplier`, the amount losses that are not getting distributed
                in a distribution can be less than 1 (base unit).
             We can actually keep track of the undistributed losses in a distribution
                and try to distribute it in the next distribution.
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
        @dev    Prepares losses for a withdrawal.
        @dev    It emits a `LossesWithdrawn` event if the amount of withdrawn losses is greater than 0.
        @return recognizableDividend The amount of dividend losses that can be recognized.
     */
    function _prepareLossesWithdraw() internal returns (uint256 recognizableDividend) {
        recognizableDividend = recognizableLossesOf(msg.sender);

        uint256 _recognizedLosses    = recognizedLosses[msg.sender].add(recognizableDividend);
        recognizedLosses[msg.sender] = _recognizedLosses;

        emit LossesRecognized(msg.sender, recognizableDividend, _recognizedLosses);
    }

    function recognizableLossesOf(address account) public override view returns (uint256) {
        return accumulativeLossesOf(account).sub(recognizedLosses[account]);
    }

    function recognizedLossesOf(address account) external override view returns (uint256) {
        return recognizedLosses[account];
    }

    function accumulativeLossesOf(address account) public override view returns (uint256) {
        return
            lossesPerShare
                .mul(balanceOf(account))
                .toInt256Safe()
                .add(lossesCorrection[account])
                .toUint256Safe() / pointsMultiplier;
    }

    /**
        @dev   Transfers tokens from one account to another. Updates pointsCorrection to keep funds unchanged.
        @dev         It emits two `LossesCorrectionUpdated` events, one for the sender and one for the receiver.
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

        int256 _lossesCorrection    = lossesPerShare.mul(value).toInt256Safe();
        int256 lossesCorrectionFrom = lossesCorrection[from].add(_lossesCorrection);
        lossesCorrection[from]      = lossesCorrectionFrom;
        int256 lossesCorrectionTo   = lossesCorrection[to].sub(_lossesCorrection);
        lossesCorrection[to]        = lossesCorrectionTo;

        emit LossesCorrectionUpdated(from, lossesCorrectionFrom);
        emit LossesCorrectionUpdated(to,   lossesCorrectionTo);
    }

    /**
        @dev   Mints tokens to an account. Updates lossesCorrection to keep losses unchanged.
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
        @dev   Burns an amount of the token of a given account. Updates lossesCorrection to keep losses unchanged.
        @dev   It emits a `LossesCorrectionUpdated` event.
        @param account The account from which tokens will be burnt.
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

    function updateLossesReceived() public override virtual {
        int256 newLosses = _updateLossesBalance();

        if (newLosses <= 0) return;

        _distributeLosses(newLosses.toUint256Safe());
    }

    /**
        @dev Recognizes all recognizable losses for an account using loss accounting.
     */
    function _recognizeLosses() internal virtual returns (uint256 losses) { }

    /**
        @dev    Updates the current losses balance and returns the difference of the new and previous losses balance.
        @return A int256 representing the difference of the new and previous losses balance.
     */
    function _updateLossesBalance() internal virtual returns (int256) { }
}
