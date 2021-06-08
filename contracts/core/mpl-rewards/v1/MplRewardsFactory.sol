// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "../../globals/v1/interfaces/IMapleGlobals.sol";

import "./MplRewards.sol";

/// @title MplRewardsFactory instantiates MplRewards contracts.
contract MplRewardsFactory {

    IMapleGlobals public globals;  // Instance of MapleGlobals, used to retrieve the current Governor.

    mapping(address => bool) public isMplRewards;  // True only if an MplRewards was created by this factory.

    event MplRewardsCreated(address indexed rewardsToken, address indexed stakingToken, address indexed mplRewards, address owner);

    constructor(address _globals) public {
        globals = IMapleGlobals(_globals);
    }

    /**
        @dev   Updates the MapleGlobals instance. Only the Governor can call this function.
        @param _globals Address of new MapleGlobals contract.
    */
    function setGlobals(address _globals) external {
        require(msg.sender == globals.governor(), "RF:NOT_GOV");
        globals = IMapleGlobals(_globals);
    }

    /**
        @dev   Instantiates a MplRewards contract. Only the Governor can call this function.
        @dev   It emits a `MplRewardsCreated` event.
        @param rewardsToken Address of the rewards token (will always be MPL).
        @param stakingToken Address of the staking token (token used to stake to earn rewards).
                            (i.e., Pool address for PoolFDT mining, StakeLocker address for staked BPT mining.)
        @return mplRewards  Address of the instantiated MplRewards.
    */
    function createMplRewards(address rewardsToken, address stakingToken) external returns (address mplRewards) {
        require(msg.sender == globals.governor(), "RF:NOT_GOV");
        mplRewards               = address(new MplRewards(rewardsToken, stakingToken, msg.sender));
        isMplRewards[mplRewards] = true;

        emit MplRewardsCreated(rewardsToken, stakingToken, mplRewards, msg.sender);
    }

}
