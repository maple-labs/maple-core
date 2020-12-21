interface ILoanTokenLocker {
    function owner() external returns (address);

    function loanToken() external returns (address);

    function fetch() external;
}
