// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "./MplRewards.sol";
import "./interfaces/IMapleGlobals.sol";

/// @title MplRewardsFactory instantiates MplRewards contracts.
contract MplRewardsFactory {

    IMapleGlobals public globals;  // Address of globals contract used to retrieve current governor

    mapping(address => bool) public isMplRewards;  // True if MplRewards was created by this factory, otherwise false.

    event MplRewardsCreated(address indexed rewardsToken, address indexed stakingToken, address indexed mplRewards, address owner);

    constructor(address _globals) public {
        globals = IMapleGlobals(_globals);
    }

    /**
        @dev Update the MapleGlobals contract. Only the Governor can call this function.
        @param _globals Address of new MapleGlobals contract
    */
    function setGlobals(address _globals) external {
        require(msg.sender == globals.governor(), "RF:NOT_GOV");
        globals = IMapleGlobals(_globals);
    }

    /**
        @dev Instantiate a MplRewards contract. Only the Governor can call this function.
        @dev It emits a `MplRewardsCreated` event.
        @param rewardsToken Address of the rewardsToken (will always be MPL).
        @param stakingToken Address of the stakingToken (token used to stake to earn rewards).
                            (i.e., Pool address for PoolFDT mining, StakeLocker address for staked BPT mining.)
        @return mplRewards Address of the instantiated MplRewards.
    */
    function createMplRewards(address rewardsToken, address stakingToken) external returns (address mplRewards) {
        require(msg.sender == globals.governor(), "RF:NOT_GOV");
        mplRewards               = address(new MplRewards(rewardsToken, stakingToken, msg.sender));
        isMplRewards[mplRewards] = true;

        emit MplRewardsCreated(rewardsToken, stakingToken, mplRewards, msg.sender);
    }
}
