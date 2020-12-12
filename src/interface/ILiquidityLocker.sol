// SPDX-License-Identifier: MIT
pragma solidity ^0.6.11;

interface ILiquidityLocker {
<<<<<<< HEAD:contracts/interface/ILiquidityLocker.sol
    function fundLoan(address _loanVault,address _loanTokenLocker, uint256 _amt) external;
=======
    function fundLoan(address _loanVault, uint256 _amt) external;
>>>>>>> ebd516a... feat: update OZ deps, switch pragma to 0.6.11, compiles with dapp framework:src/interface/ILiquidityLocker.sol
}
