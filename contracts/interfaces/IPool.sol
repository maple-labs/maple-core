// SPDX-License-Identifier: MIT
pragma solidity 0.6.11;

interface IPool {
    function poolDelegate() external view returns (address);

    function admins(address) external view returns (bool);

    function deposit(uint256) external;

    function poolState() external view returns(uint256);

    function deactivate(uint256) external;

    function finalize() external;

    function claim(address, address) external returns(uint256[7] memory);

    function testValue() external view returns(uint256);

    function setPenaltyDelay(uint256) external;

    function setLockupPeriod(uint256) external;

    function setPrincipalPenalty(uint256) external;

    function fundLoan(address, address, uint256) external;

    function withdraw(uint256) external;

    function superFactory() external view returns (address);
    
    function setAllowlistStakeLocker(address, bool) external;

    function claimableFunds(address) external view returns(uint256, uint256, uint256);
}
