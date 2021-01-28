// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;

interface IPool {
    function poolDelegate() external view returns (address);

    function deposit(uint256) external;

    function poolState() external view returns(uint256);

    function deactivate(uint256) external;

    function finalize() external;

    function claim(address, address) external returns(uint256[6] memory);

    function testValue() external view returns(uint256);

    function setPenaltyDelay(uint256) external;

    function setPrincipalPenalty(uint256) external;

    function fundLoan(address, address, uint256) external;

    function superFactory() external view returns (address);
}
