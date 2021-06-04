// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

interface ILoanFactory {

    function CL_FACTORY() external view returns (uint8);

    function FL_FACTORY() external view returns (uint8);

    function INTEREST_CALC_TYPE() external view returns (uint8);

    function LATEFEE_CALC_TYPE() external view returns (uint8);

    function PREMIUM_CALC_TYPE() external view returns (uint8);

    function globals() external view returns (address);

    function loansCreated() external view returns (uint256);

    function loans(uint256) external view returns (address);

    function isLoan(address) external view returns (bool);

    function loanFactoryAdmins(address) external view returns (bool);

    function setGlobals(address) external;

    function createLoan(address, address, address, address, uint256[5] memory, address[3] memory) external returns (address);

    function setLoanFactoryAdmin(address, bool) external;

    function pause() external;

    function unpause() external;

}
