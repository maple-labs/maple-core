// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.6.11;

import "core/custodial-ownership-token/v1/test/accounts/ERC2258Account.sol";

import "../../interfaces/IMplRewards.sol";

contract MplRewardsStaker is ERC2258Account {
    function mplRewards_stake(IMplRewards mplRewards, uint256 amount) external {
        mplRewards.stake(amount);
    }

    function try_mplRewards_stake(address mplRewards, uint256 amount) external returns (bool ok) {
        (ok,) = mplRewards.call(abi.encodeWithSignature("stake(uint256)", amount));
    }

    function mplRewards_withdraw(IMplRewards mplRewards, uint256 amount) external {
        mplRewards.withdraw(amount);
    }

    function try_mplRewards_withdraw(address mplRewards, uint256 amount) external returns (bool ok) {
        (ok,) = mplRewards.call(abi.encodeWithSignature("withdraw(uint256)", amount));
    }

    function mplRewards_getReward(IMplRewards mplRewards) external {
        mplRewards.getReward();
    }

    function try_mplRewards_getReward(address mplRewards) external returns (bool ok) {
        (ok,) = mplRewards.call(abi.encodeWithSignature("getReward()"));
    }

    function mplRewards_exit(IMplRewards mplRewards) external {
        mplRewards.exit();
    }

    function try_mplRewards_exit(address mplRewards) external returns (bool ok) {
        (ok,) = mplRewards.call(abi.encodeWithSignature("exit()"));
    }
}
