// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "./MplRewards.sol";
import "./interfaces/IGlobals.sol";

/// @title MplRewardsFactory instantiates MplRewards contracts.
contract MplRewardsFactory {

    IGlobals public globals;  // Address of globals contract used to retrieve current governor

    mapping(address => bool) public isMplRewards;  // True if MplRewards was created by this factory, otherwise false.

    event MplRewardsCreated(address indexed rewardsToken, address indexed stakingToken, address mplRewards, address owner);

    constructor(address _globals) public {
        globals = IGlobals(_globals);
    }

    /**
        @dev Update the MapleGlobals contract
        @param _globals Address of new MapleGlobals contract
    */
    function setGlobals(address _globals) external {
        require(msg.sender == globals.governor());
        globals = IGlobals(_globals);
    }

    /**
        @dev Instantiate a MplRewards contract.
        @param rewardsToken Address of the rewardsToken (will always be MPL)
        @param stakingToken Address of the stakingToken (token used to stake to earn rewards)
                            (i.e., Pool address for PoolFDT mining, StakeLocker address for staked BPT mining)
        @return Address of the instantiated MplRewards
    */
    function createMplRewards(address rewardsToken, address stakingToken) external returns (address) {
        require(msg.sender == globals.governor(), "MplRewardsFactory:UNAUTHORIZED");
        address mplRewards       = address(new MplRewards(rewardsToken, stakingToken, msg.sender));
        isMplRewards[mplRewards] = true;

        emit MplRewardsCreated(rewardsToken, stakingToken, mplRewards, msg.sender);
        return mplRewards;
    }
}
