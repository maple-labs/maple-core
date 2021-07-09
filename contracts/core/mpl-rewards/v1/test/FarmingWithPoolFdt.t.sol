// SPDX-License-Identifier: MIT
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

contract PoolCustodialTest is CustodialTestHelper {

    using SafeMath for uint256;

    uint256 principalOut;        // Total outstanding principal of Pool
    uint256 liquidityLockerBal;  // Total liquidityAsset balance of LiquidityLocker
    uint256 fdtTotalSupply;      // PoolFDT total supply
    uint256 interestSum;         // FDT accounting of interest earned
    uint256 poolLosses;          // FDT accounting of recognizable losses

    TestObj withdrawableFundsOf_fay;  // FDT accounting of interest
    TestObj withdrawableFundsOf_fez;  // FDT accounting of interest
    TestObj withdrawableFundsOf_fox;  // FDT accounting of interest

    TestObj mplEarnings_fay;  // MPL earnings from yield farming
    TestObj mplEarnings_fez;  // MPL earnings from yield farming
    TestObj mplEarnings_fox;  // MPL earnings from yield farming

    function setUp() public {
        setupFarmingEcosystem();
        setUpMplRewards(address(pool1));
        createFarmers();
    }

    function updateState() internal {
        // Update pre state
        withdrawableFundsOf_fay.pre = withdrawableFundsOf_fay.post;
        withdrawableFundsOf_fez.pre = withdrawableFundsOf_fez.post;
        withdrawableFundsOf_fox.pre = withdrawableFundsOf_fox.post;

        mplEarnings_fay.pre = mplEarnings_fay.post;
        mplEarnings_fez.pre = mplEarnings_fez.post;
        mplEarnings_fox.pre = mplEarnings_fox.post;

        // Update post state
        principalOut       = pool1.principalOut();
        liquidityLockerBal = usdc.balanceOf(pool1.liquidityLocker());
        fdtTotalSupply     = pool1.totalSupply();
        interestSum        = pool1.interestSum();
        poolLosses         = pool1.poolLosses();

        withdrawableFundsOf_fay.post = pool1.withdrawableFundsOf(address(fay));
        withdrawableFundsOf_fez.post = pool1.withdrawableFundsOf(address(fez));
        withdrawableFundsOf_fox.post = pool1.withdrawableFundsOf(address(fox));

        mplEarnings_fay.post = mplRewards.earned(address(fay));
        mplEarnings_fez.post = mplRewards.earned(address(fez));
        mplEarnings_fox.post = mplRewards.earned(address(fox));
    }

    function test_interest_plus_farming(uint256 depositAmt1, uint256 depositAmt2, uint256 depositAmt3) public {
        uint256 start = block.timestamp;

        // Set up fuzzing amounts
        depositAmt1 = constrictToRange(depositAmt1, 1000 * USD, 10_000_000 * USD, true);
        depositAmt2 = constrictToRange(depositAmt2, 1000 * USD, 10_000_000 * USD, true);
        depositAmt3 = constrictToRange(depositAmt3, 1000 * USD, 10_000_000 * USD, true);

        /**********************************************************************/
        /*** Fay and Fez both deposit into the pool and start yield farming ***/
        /**********************************************************************/
        setUpFarming(300_000 * WAD, 180 days);

        mintFundsAndDepositIntoPool(fay, pool1, depositAmt1, depositAmt1);
        stakeIntoFarm(fay, toWad(depositAmt1));

        mintFundsAndDepositIntoPool(fez, pool1, depositAmt2, depositAmt2);
        stakeIntoFarm(fez, toWad(depositAmt2));

        uint256 totalDeposits = depositAmt1 + depositAmt2;

        /**********************/
        /*** Pre-Loan State ***/
        /**********************/
        updateState();

        assertEq(withdrawableFundsOf_fay.post, 0);
        assertEq(withdrawableFundsOf_fez.post, 0);
        assertEq(withdrawableFundsOf_fox.post, 0);

        assertEq(mplEarnings_fay.post, 0);
        assertEq(mplEarnings_fez.post, 0);
        assertEq(mplEarnings_fox.post, 0);

        /*************************************************************/
        /*** Create Loan, draw down, make payment, claim from Pool ***/
        /*************************************************************/
        {
            uint256[5] memory specs = [500, 180, 30, totalDeposits, 2000];
            createLoan(specs);
            pat.fundLoan(address(pool1), address(loan1), address(dlFactory1), totalDeposits);
            drawdown(loan1, bob, totalDeposits);
            hevm.warp(loan1.nextPaymentDue());  // Will affect yield farming
            doPartialLoanPayment(loan1, bob);
            pat.claim(address(pool1), address(loan1), address(dlFactory1));
        }

        // Update variables to reflect change in accounting from last dTime
        updateState();
        uint256 dTime = block.timestamp - start;

        uint256 interest          = interestSum;
        uint256 totalMplDisbursed = mplRewards.rewardRate() * dTime;

        uint256 poolApy = toApy(interest,          totalDeposits, dTime);
        uint256 mplApy  = toApy(totalMplDisbursed, toWad(totalDeposits), dTime);

        /***********************************/
        /*** Post One Loan Payment State ***/
        /***********************************/
        withinPrecision(withdrawableFundsOf_fay.post, calcPortion(depositAmt1, interestSum, totalDeposits), 6);
        withinPrecision(withdrawableFundsOf_fez.post, calcPortion(depositAmt2, interestSum, totalDeposits), 6);

        assertEq(withdrawableFundsOf_fox.post, 0);

        withinPrecision(mplEarnings_fay.post, calcPortion(depositAmt1, totalMplDisbursed, totalDeposits), 10);
        withinPrecision(mplEarnings_fez.post, calcPortion(depositAmt2, totalMplDisbursed, totalDeposits), 10);

        assertEq(mplEarnings_fox.post, 0);

        withinDiff(toApy(withdrawableFundsOf_fay.post, depositAmt1, dTime), poolApy, 1);
        withinDiff(toApy(withdrawableFundsOf_fez.post, depositAmt2, dTime), poolApy, 1);

        withinDiff(toApy(mplEarnings_fay.post, toWad(depositAmt1), dTime), mplApy, 1);
        withinDiff(toApy(mplEarnings_fez.post, toWad(depositAmt2), dTime), mplApy, 1);

        /***********************************************************/
        /*** Fox deposits into the pool and starts yield farming ***/
        /***********************************************************/
        mintFundsAndDepositIntoPool(fox, pool1, depositAmt3, depositAmt3);
        stakeIntoFarm(fox, toWad(depositAmt3));

        totalDeposits = totalDeposits + depositAmt3;

        /********************************************/
        /*** Make second payment, claim from Pool ***/
        /********************************************/
        hevm.warp(loan1.nextPaymentDue() - 6 hours);  // Will affect yield farming (using a different timestamp just for the sake of yield farming assertions)
        doPartialLoanPayment(loan1, bob);
        pat.claim(address(pool1), address(loan1), address(dlFactory1));

        // Update variables to reflect change in accounting from last dTime
        updateState();
        dTime = block.timestamp - start - dTime;

        totalMplDisbursed = mplRewards.rewardRate() * dTime;
        interest          = interestSum - interest;

        poolApy = toApy(interest,          totalDeposits, dTime);
        mplApy  = toApy(totalMplDisbursed, toWad(totalDeposits), dTime);

        /***********************************/
        /*** Post One Loan Payment State ***/
        /***********************************/
        withinPrecision(withdrawableFundsOf_fay.post, withdrawableFundsOf_fay.pre + calcPortion(depositAmt1, interest, totalDeposits), 6);
        withinPrecision(withdrawableFundsOf_fez.post, withdrawableFundsOf_fez.pre + calcPortion(depositAmt2, interest, totalDeposits), 6);
        withinPrecision(withdrawableFundsOf_fox.post,                               calcPortion(depositAmt3, interest, totalDeposits), 6);

        withinPrecision(mplEarnings_fay.post, mplEarnings_fay.pre + calcPortion(depositAmt1, totalMplDisbursed, totalDeposits), 10);
        withinPrecision(mplEarnings_fez.post, mplEarnings_fez.pre + calcPortion(depositAmt2, totalMplDisbursed, totalDeposits), 10);
        withinPrecision(mplEarnings_fox.post,                       calcPortion(depositAmt3, totalMplDisbursed, totalDeposits), 10);

        withinDiff(toApy(withdrawableFundsOf_fay.post - withdrawableFundsOf_fay.pre, depositAmt1, dTime), poolApy, 1);
        withinDiff(toApy(withdrawableFundsOf_fez.post - withdrawableFundsOf_fez.pre, depositAmt2, dTime), poolApy, 1);
        withinDiff(toApy(withdrawableFundsOf_fox.post,                               depositAmt3, dTime), poolApy, 1);

        withinDiff(toApy(mplEarnings_fay.post - mplEarnings_fay.pre, toWad(depositAmt1), dTime), mplApy, 1);
        withinDiff(toApy(mplEarnings_fez.post - mplEarnings_fez.pre, toWad(depositAmt2), dTime), mplApy, 1);
        withinDiff(toApy(mplEarnings_fox.post,                       toWad(depositAmt3), dTime), mplApy, 1);
    }

    function test_custody_and_transfer(uint256 depositAmt, uint256 custodyAmt1, uint256 custodyAmt2) public {
        custody_and_transfer(depositAmt, custodyAmt1, custodyAmt2, true, IStakeToken(address(pool1)));
    }

    function test_custody_and_withdraw(uint256 depositAmt, uint256 custodyAmt) public {
        custody_and_withdraw(depositAmt, custodyAmt, true, IStakeToken(address(pool1)));
    }

    function test_transferByCustodian(uint256 depositAmt, uint256 custodyAmt) public {
        fdt_transferByCustodian(depositAmt, custodyAmt, true, IStakeToken(address(pool1)));
    }

    function test_stake() public {
        stake_test(true, 1000, 100, IStakeToken(address(pool1)));
    }

    function test_withdraw() public {
        withdraw_test(true, 1000, 100, IStakeToken(address(pool1)));
    }
}
