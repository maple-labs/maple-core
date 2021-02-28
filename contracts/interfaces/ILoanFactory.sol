// SPDX-License-Identifier: MIT
pragma solidity 0.6.11;

interface ILoanFactory {
    function isLoan(address) external view returns (bool);

    function loans(uint256)  external view returns (address);

    function globals() external view returns (address);
    
    function createLoan(address, address, address, address, uint256[6] memory, address[3] memory) external returns (address);
}
