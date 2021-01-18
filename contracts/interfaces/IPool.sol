// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;

interface IPool {
    function poolDelegate() external view returns (address);

    function isDefunct() external view returns (bool);

    function poolState() external view returns (uint256);

    function finalize() external;

    function deposit(uint256) external;

    function deactivate(uint256) external;

    function claim(address, address) external returns(uint[5] memory);

    function setInterestDelay(uint256) external;

    function setPrincipalPenalty(uint256) external;

}
