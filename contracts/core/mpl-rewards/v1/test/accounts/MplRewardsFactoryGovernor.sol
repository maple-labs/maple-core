// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.6.11;

import "../../interfaces/IMplRewardsFactory.sol";

contract MplRewardsFactoryGovernor {
    function mplRewards_setGlobals(IMplRewardsFactory mplRewardsFactory, address newGlobals) external {
        mplRewardsFactory.setGlobals(newGlobals);
    }

    function try_mplRewards_setGlobals(address mplRewardsFactory, address newGlobals) external returns (bool ok) {
        (ok,) = mplRewardsFactory.call(abi.encodeWithSignature("setGlobals(address)", newGlobals));
    }

    function mplRewards_createMplRewards(IMplRewardsFactory mplRewardsFactory, address rewardsToken, address stakingToken) external returns (address mplRewards) {
        return mplRewardsFactory.createMplRewards(rewardsToken, stakingToken);
    }

    function try_mplRewards_createMplRewards(address mplRewardsFactory, address rewardsToken, address stakingToken) external returns (bool ok) {
        (ok,) = mplRewardsFactory.call(abi.encodeWithSignature("createMplRewards(address,address)", rewardsToken, stakingToken));
    }
}
