// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;

import "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "lib/openzeppelin-contracts/contracts/math/SafeMath.sol";
import "lib/openzeppelin-contracts/contracts/math/SignedSafeMath.sol";
import "./IFDT.sol";
import "../math/SafeMathUint.sol";
import "../math/SafeMathInt.sol";

abstract contract PoolFDT is IFDT, ERC20 {
    using SafeMath       for uint256;
    using SafeMathUint   for uint256;
    using SignedSafeMath for  int256;
    using SafeMathInt    for  int256;

    uint256 public interestSum;   // Sum of all withdrawable interest 
    uint256 public bptShortfall;  // Sum of all unrecognized losses 

    uint256 public interestBalance;  // The amount of earned interest present and accounted for in this contract.
    uint256 public lossesBalance;    // The amount of losses present and accounted for in this contract.

    uint256 internal constant pointsMultiplier = 2 ** 128;

    uint256 internal pointsPerShare;
    uint256 internal lossesPerShare;

    mapping(address => int256)  internal pointsCorrection;
    mapping(address => int256)  internal lossesCorrection;

    mapping(address => uint256) internal withdrawnFunds;
    mapping(address => uint256) internal recognizedLosses;

    /**
     * @dev This event emits when new losses are distributed
     * @param by the address of the sender who distributed losses
     * @param lossesDistributed the amount of losses received for distribution
     */
    event LossesDistributed(address indexed by, uint256 lossesDistributed);

    /**
     * @dev This event emits when distributed losses are recognized by a token holder.
     * @param by the address of the receiver of losses
     * @param lossesRecognized the amount of losses that were recognized
     */
    event LossesRecognized(address indexed by, uint256 lossesRecognized);

    constructor(string memory name, string memory symbol) ERC20(name, symbol) public { }

    /**
     * prev. distributeDividends
     * @dev Distributes funds to token holders.
     * @dev It reverts if the total supply of tokens is 0.
     * It emits the `FundsDistributed` event if the amount of received funds is greater than 0.
     * About undistributed funds:
     *   In each distribution, there is a small amount of funds which does not get distributed,
     *     which is `(msg.value * pointsMultiplier) % totalSupply()`.
     *   With a well-chosen `pointsMultiplier`, the amount funds that are not getting distributed
     *     in a distribution can be less than 1 (base unit).
     *   We can actually keep track of the undistributed funds in a distribution
     *     and try to distribute it in the next distribution ....... todo implement
     */
    function _distributeFunds(uint256 value) internal {
        require(totalSupply() > 0, "FDT:SUPPLY_EQ_ZERO");

        if (value > 0) {
            pointsPerShare = pointsPerShare.add(value.mul(pointsMultiplier) / totalSupply());
            emit FundsDistributed(msg.sender, value);
            emit PointsPerShareUpdated(pointsPerShare);
        }
    }

    /**
     * prev. distributeDividends
     * @dev Distributes losses to token holders.
     * @dev It reverts if the total supply of tokens is 0.
     * It emits the `FundsDistributed` event if the amount of received losses is greater than 0.
     * About undistributed losses:
     *   In each distribution, there is a small amount of losses which does not get distributed,
     *     which is `(msg.value * pointsMultiplier) % totalSupply()`.
     *   With a well-chosen `pointsMultiplier`, the amount losses that are not getting distributed
     *     in a distribution can be less than 1 (base unit).
     *   We can actually keep track of the undistributed losses in a distribution
     *     and try to distribute it in the next distribution ....... todo implement
     */
    function _distributeLosses(uint256 value) internal {
        require(totalSupply() > 0, "FDT:SUPPLY_EQ_ZERO");

        if (value > 0) {
            lossesPerShare = lossesPerShare.add(value.mul(pointsMultiplier) / totalSupply());
            emit LossesDistributed(msg.sender, value);
            emit LossesPerShareUpdated(lossesPerShare);
        }
    }

    /**
     * @dev Prepares funds withdrawal
     * @dev It emits a `FundsWithdrawn` event if the amount of withdrawn ether is greater than 0.
     */
    
    function _prepareWithdraw() internal returns (uint256) {
        uint256 _withdrawableDividend = withdrawableFundsOf(msg.sender);

        withdrawnFunds[msg.sender] = withdrawnFunds[msg.sender].add(_withdrawableDividend);

        emit FundsWithdrawn(msg.sender, _withdrawableDividend, withdrawnFunds[msg.sender]);

        return _withdrawableDividend;
    }

    /**
     * @dev Prepares losses withdrawal
     * @dev It emits a `LossesWithdrawn` event if the amount of withdrawn losses is greater than 0.
     */
    
    function _prepareLossesWithdraw() internal returns (uint256) {
        uint256 _recognizeableDividend = recognizeableLossesOf(msg.sender);

        recognizedLosses[msg.sender] = recognizedLosses[msg.sender].add(_recognizeableDividend);

        emit LossesRecognized(msg.sender, _recognizeableDividend, recognizedLosses[msg.sender]);

        return _recognizeableDividend;
    }

    /**
     * @dev View the amount of funds that an address can withdraw.
     * @param _owner The address of a token holder.
     * @return The amount funds that `_owner` can withdraw.
     */
    function withdrawableFundsOf(address _owner) public view override returns (uint256) {
        return accumulativeFundsOf(_owner).sub(withdrawnFunds[_owner]);
    }

    /**
     * @dev View the amount of losses that an address can withdraw.
     * @param _owner The address of a token holder.
     * @return The amount losses that `_owner` can withdraw.
     */
    function recognizeableLossesOf(address _owner) public view returns (uint256) {
        return accumulativeLossesOf(_owner).sub(recognizedLosses[_owner]);
    }

    /**
     * @dev View the amount of funds that an address has withdrawn.
     * @param _owner The address of a token holder.
     * @return The amount of funds that `_owner` has withdrawn.
     */
    function withdrawnFundsOf(address _owner) public view returns (uint256) {
        return withdrawnFunds[_owner];
    }

    /**
     * @dev View the amount of losses that an address has recognized.
     * @param _owner The address of a token holder.
     * @return The amount of losses that `_owner` has recognized.
     */
    function recognizedLossesOf(address _owner) public view returns (uint256) {
        return recognizedLosses[_owner];
    }

    /**
     * @dev View the amount of funds that an address has earned in total.
     * @dev accumulativeFundsOf(_owner) = withdrawableFundsOf(_owner) + withdrawnFundsOf(_owner)
     * = (pointsPerShare * balanceOf(_owner) + pointsCorrection[_owner]) / pointsMultiplier
     * @param _owner The address of a token holder.
     * @return The amount of funds that `_owner` has earned in total.
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
     * @dev View the amount of losses that an address has earned in total.
     * @dev accumulativeLossesOf(_owner) = withdrawableLossesOf(_owner) + withdrawnLossesOf(_owner)
     * = (pointsPerShare * balanceOf(_owner) + pointsCorrection[_owner]) / pointsMultiplier
     * @param _owner The address of a token holder.
     * @return The amount of losses that `_owner` has earned in total.
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
     * @dev Internal function that transfer tokens from one address to another.
     * Update pointsCorrection to keep funds unchanged.
     * @param from The address to transfer from.
     * @param to The address to transfer to.
     * @param value The amount to be transferred.
     */
    function _transfer(
        address from,
        address to,
        uint256 value
    ) internal virtual override {
        super._transfer(from, to, value);

        int256 _interestCorrection = pointsPerShare.mul(value).toInt256Safe();
        pointsCorrection[from]     = pointsCorrection[from].add(_interestCorrection);
        pointsCorrection[to]       = pointsCorrection[to].sub(_interestCorrection);

        int256 _lossesCorrection = lossesPerShare.mul(value).toInt256Safe();
        lossesCorrection[from]   = lossesCorrection[from].add(_lossesCorrection);
        lossesCorrection[to]     = lossesCorrection[to].sub(_lossesCorrection);

        emit PointsCorrectionUpdated(from, pointsCorrection[from]);
        emit PointsCorrectionUpdated(to,   pointsCorrection[to]);

        emit LossesCorrectionUpdated(from, lossesCorrection[from]);
        emit LossesCorrectionUpdated(to,   lossesCorrection[to]);
    }

    /**
     * @dev Internal function that mints tokens to an account.
     * Update pointsCorrection to keep funds unchanged.
     * @param account The account that will receive the created tokens.
     * @param value The amount that will be created.
     */
    function _mint(address account, uint256 value) internal virtual override {
        super._mint(account, value);

        pointsCorrection[account] = pointsCorrection[account].sub(
            (pointsPerShare.mul(value)).toInt256Safe()
        );

        lossesCorrection[account] = lossesCorrection[account].sub(
            (lossesPerShare.mul(value)).toInt256Safe()
        );

        emit PointsCorrectionUpdated(account, pointsCorrection[account]);
        emit LossesCorrectionUpdated(account, lossesCorrection[account]);
    }

    /**
     * @dev Internal function that burns an amount of the token of a given account.
     * Update pointsCorrection to keep funds unchanged.
     * @param account The account whose tokens will be burnt.
     * @param value The amount that will be burnt.
     */
    function _burn(address account, uint256 value) internal virtual override {
        super._burn(account, value);

        pointsCorrection[account] = pointsCorrection[account].add(
            (pointsPerShare.mul(value)).toInt256Safe()
        );

        lossesCorrection[account] = lossesCorrection[account].add(
            (lossesPerShare.mul(value)).toInt256Safe()
        );

        emit PointsCorrectionUpdated(account, pointsCorrection[account]);
        emit LossesCorrectionUpdated(account, lossesCorrection[account]);
    }

    /**
     * @dev Register a payment of funds in tokens. May be called directly after a deposit is made.
     * @dev Calls _updateFundsTokenBalance(), whereby the contract computes the delta of the previous and the new
     * funds token balance and increments the total received funds (cumulative) by delta by calling _registerFunds()
     */
    function updateFundsReceived() public virtual {
        int256 newFunds = _updateFundsTokenBalance();

        if (newFunds > 0) {
            _distributeFunds(newFunds.toUint256Safe());
        }
    }

    /**
     * @dev Register a loss. May be called directly after a shortfall after BPT burning occurs.
     * @dev Calls _updateLossesTokenBalance(), whereby the contract computes the delta of the previous and the new
     * funds token balance and increments the total received funds (cumulative) by delta by calling _registerLosses()
     */
    function updateLossesReceived() public virtual {
        int256 newLosses = _updateLossesBalance();

        if (newLosses > 0) {
            _distributeLosses(newLosses.toUint256Safe());
        }
    }

    /**
        @dev Withdraws all claimable interest from the `liquidityLocker` for a user using `interestSum` accounting.
    */
    function recognizeLosses() internal returns (uint256 losses) {
        losses = _prepareLossesWithdraw();

        bptShortfall = bptShortfall.sub(losses);

        _updateLossesBalance();
    }

    /**
        @dev Updates the current funds token balance and returns the difference of new and previous funds token balances.
        @return A int256 representing the difference of the new and previous funds token balance.
    */
    function _updateFundsTokenBalance() internal returns (int256) {
        uint256 _prevFundsTokenBalance = interestBalance;

        interestBalance = interestSum;

        return int256(interestBalance).sub(int256(_prevFundsTokenBalance));
    }

    /**
        @dev Updates the current funds token balance and returns the difference of new and previous funds token balances.
        @return A int256 representing the difference of the new and previous funds token balance.
    */
    function _updateLossesBalance() internal returns (int256) {
        uint256 _prevLossesTokenBalance = lossesBalance;

        lossesBalance = bptShortfall;

        return int256(lossesBalance).sub(int256(_prevLossesTokenBalance));
    }
}
