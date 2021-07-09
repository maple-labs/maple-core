// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import { IMapleGlobals } from "../../../globals/v1/interfaces/IMapleGlobals.sol";

/// @title MplRewardsFactory instantiates MplRewards contracts.
interface IMplRewardsFactory {

    /**
        @dev   Emits an event indicating that a MplRewards contract was created.
        @param rewardsToken The asset used for rewards.
        @param stakingToken The asset used for staking.
        @param mplRewards   The address of the MplRewards contract.
        @param owner        The owner of the MplRewards.
     */
    event MplRewardsCreated(address indexed rewardsToken, address indexed stakingToken, address indexed mplRewards, address owner);

    /**
        @dev The instance of MapleGlobals, used to retrieve the current Governor.
     */
    function globals() external view returns (IMapleGlobals);

    /**
        @param mpeRewards A MplRewards contract.
        @return Whether `mpeRewards` is a MplRewards contract.
     */
    function isMplRewards(address mpeRewards) external view returns (bool);

    /**
        @dev   Updates the MapleGlobals instance. 
        @dev   Only the Governor can call this function. 
        @param _globals Address of new MapleGlobals contract.
     */
    function setGlobals(address _globals) external;

    /**
        @dev   Instantiates a MplRewards contract. 
        @dev   Only the Governor can call this function. 
        @dev   It emits a `MplRewardsCreated` event. 
        @param rewardsToken The address of the rewards token (will always be MPL).
        @param stakingToken The address of the staking token (token used to stake to earn rewards). 
                            (i.e., Pool address for PoolFDT mining, StakeLocker address for staked BPT mining.) 
        @return mplRewards  The address of the instantiated MplRewards.
     */
    function createMplRewards(address rewardsToken, address stakingToken) external returns (address mplRewards);

}
