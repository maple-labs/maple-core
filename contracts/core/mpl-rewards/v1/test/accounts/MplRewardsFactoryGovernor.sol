// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.6.11;

import { IMplRewardsFactory } from "../../interfaces/IMplRewardsFactory.sol";

contract MplRewardsFactoryGovernor {

    function mplRewards_setGlobals(address mplRewardsFactory, address newGlobals) external {
        IMplRewardsFactory(mplRewardsFactory).setGlobals(newGlobals);
    }

    function try_mplRewards_setGlobals(address mplRewardsFactory, address newGlobals) external returns (bool ok) {
        (ok,) = mplRewardsFactory.call(abi.encodeWithSignature("setGlobals(address)", newGlobals));
    }

    function mplRewards_createMplRewards(address mplRewardsFactory, address rewardsToken, address stakingToken) external returns (address mplRewards) {
        return IMplRewardsFactory(mplRewardsFactory).createMplRewards(rewardsToken, stakingToken);
    }

    function try_mplRewards_createMplRewards(address mplRewardsFactory, address rewardsToken, address stakingToken) external returns (bool ok) {
        (ok,) = mplRewardsFactory.call(abi.encodeWithSignature("createMplRewards(address,address)", rewardsToken, stakingToken));
    }

}
