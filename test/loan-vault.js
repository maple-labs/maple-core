const { expect, assert } = require('chai')
const { BigNumber } = require('ethers')

const DAIAddress = require('../../contracts/localhost/addresses/MintableTokenDAI.address.js')
const DAIABI = require('../../contracts/localhost/abis/MintableTokenDAI.abi.js')
const USDCAddress = require('../../contracts/localhost/addresses/MintableTokenUSDC.address.js')
const USDCABI = require('../../contracts/localhost/abis/MintableTokenUSDC.abi.js')
const MPLAddress = require('../../contracts/localhost/addresses/MapleToken.address.js')
const MPLABI = require('../../contracts/localhost/abis/MapleToken.abi.js')
const WETHAddress = require('../../contracts/localhost/addresses/WETH9.address.js')
const WETHABI = require('../../contracts/localhost/abis/WETH9.abi.js')
const WBTCAddress = require('../../contracts/localhost/addresses/WBTC.address.js')
const WBTCABI = require('../../contracts/localhost/abis/WBTC.abi.js')
const LVFactoryAddress = require('../../contracts/localhost/addresses/LoanVaultFactory.address.js')
const LVFactoryABI = require('../../contracts/localhost/abis/LoanVaultFactory.abi.js')
const FLFAddress = require('../../contracts/localhost/addresses/LoanVaultFundingLockerFactory.address.js')
const FLFABI = require('../../contracts/localhost/abis/LoanVaultFundingLockerFactory.abi.js')
const CLFAddress = require('../../contracts/localhost/addresses/LoanVaultCollateralLockerFactory.address.js')
const CLFABI = require('../../contracts/localhost/abis/LoanVaultCollateralLockerFactory.abi.js')
const LALFAddress = require('../../contracts/localhost/addresses/LiquidAssetLockerFactory.address.js')
const LALFABI = require('../../contracts/localhost/abis/LiquidAssetLockerFactory.abi.js')
const GlobalsAddress = require('../../contracts/localhost/addresses/MapleGlobals.address.js')
const GlobalsABI = require('../../contracts/localhost/abis/MapleGlobals.abi.js')
const LoanVaultABI = require('../../contracts/localhost/abis/LoanVault.abi.js')


describe('LoanVault.sol', function () {

  const BUNK_ADDRESS = "0x0000000000000000000000000000000000000000";

  let DAI, USDC, MPL, WETH, WBTC, LoanVaultFactory, FundingLockerFactory, CollateralLockerFactory, Globals;

  before(async () => {
    DAI = new ethers.Contract(DAIAddress, DAIABI, ethers.provider.getSigner(0))
    USDC = new ethers.Contract(USDCAddress, USDCABI, ethers.provider.getSigner(0))
    MPL = new ethers.Contract(MPLAddress, MPLABI, ethers.provider.getSigner(0))
    WETH = new ethers.Contract(WETHAddress, WETHABI, ethers.provider.getSigner(0))
    WBTC = new ethers.Contract(WBTCAddress, WBTCABI, ethers.provider.getSigner(0))
    LoanVaultFactory = new ethers.Contract(LVFactoryAddress, LVFactoryABI, ethers.provider.getSigner(0))
    FundingLockerFactory = new ethers.Contract(FLFAddress, FLFABI, ethers.provider.getSigner(0))
    CollateralLockerFactory = new ethers.Contract(CLFAddress, CLFABI, ethers.provider.getSigner(0))
    LiquidLockerFactory = new ethers.Contract(LALFAddress, LALFABI, ethers.provider.getSigner(0))
    Globals = new ethers.Contract(GlobalsAddress, GlobalsABI, ethers.provider.getSigner(0))
  })

  let vaultAddress;

  it('instantiate loanVault from factory', async function () {

    // Confirm incrementor pre/post-checks.
    const preIncrementorValue = await LoanVaultFactory.loanVaultsCreated();

    /**
      function createLoanVault(
          address _assetRequested,
          address _assetCollateral,
          address _fundingLockerFactory,
          address _collateralLockerFactory,
          string memory name,
          string memory symbol,
          address _mapleGlobals
      ) 
    */

    // Create the loan vault.
    const contract = await LoanVaultFactory.createLoanVault(
      DAIAddress,
      WETHAddress,
      FLFAddress,
      CLFAddress,
      'QuantFundLoan',
      'QFL',
      GlobalsAddress
    );

    const postIncrementorValue = await LoanVaultFactory.loanVaultsCreated();

    expect(
      parseInt(postIncrementorValue["_hex"]) - 1
    ).to.equals(
      parseInt(preIncrementorValue["_hex"])
    );

    // Fetch address of the LoanVault, confirm the address passes isLoanVault() identifcation check.
    const loanVaultAddress = await LoanVaultFactory.getLoanVault(preIncrementorValue);
    vaultAddress = loanVaultAddress;

    const isLoanVault = await LoanVaultFactory.isLoanVault(loanVaultAddress);

    expect(isLoanVault);
    
  })
  
  it('confirm loanVault borrower address', async function () {
    LoanVault = new ethers.Contract(vaultAddress, LoanVaultABI, ethers.provider.getSigner(0))
    const accounts = await ethers.provider.listAccounts()
    const borrower = await LoanVault.borrower()
    expect(borrower).to.equals(accounts[0]);
  })

  it('block locker creation from external (fails isLoanVault check)', async function () {
    
    await expect(
      FundingLockerFactory.newLocker(DAIAddress)
    ).to.be.revertedWith("LoanVaultFundingLockerFactory::newLocker:ERR_MSG_SENDER_NOT_LOAN_VAULT");

    await expect(
      CollateralLockerFactory.newLocker(WETHAddress)
    ).to.be.revertedWith("LoanVaultCollateralLockerFactory::newLocker:ERR_MSG_SENDER_NOT_LOAN_VAULT");

  })

  it('prepareLoan() with invalid input parameters', async function () {
    
    /** 
     *  @notice Provide the specifications of the loan, transition state from Initialized to Funding.
     *  @param _details The specifications of the loan.
     *      _details[0] = APR_BIPS
     *      _details[1] = NUMBER_OF_PAYMENTS
     *      _details[2] = PAYMENT_INTERVAL_SECONDS
     *      _details[3] = MIN_RAISE
     *      _details[4] = DESIRED_RAISE
     *      _details[5] = COLLATERAL_AT_DESIRED_RAISE
     *      @param _repaymentCalculator The calculator used for interest and principal repayment calculations.
     *      @param _premiumCalculator The calculator used for call premiums.
     * 
     *  function prepareLoan(
     *      uint[6] memory _details,
     *      address _repaymentCalculator,
     *      address _premiumCalculator
     *  )
    */ 


    await expect(
      LoanVault.prepareLoan(
        [1000, 0, 0, 0, 0, 0],
        BUNK_ADDRESS,
        BUNK_ADDRESS
      )
    ).to.be.revertedWith('LoanVault::prepareLoan:ERR_NUMBER_OF_PAYMENTS_LESS_THAN_1')

    await expect(
      LoanVault.prepareLoan(
        [1000, 1, 0, 0, 0, 0],
        BUNK_ADDRESS,
        BUNK_ADDRESS
      )
    ).to.be.revertedWith('LoanVault::prepareLoan:ERR_INVALID_PAYMENT_INTERVAL_SECONDS')

    await expect(
      LoanVault.prepareLoan(
        [1000, 1, 2592000, 0, 0, 0],
        BUNK_ADDRESS,
        BUNK_ADDRESS
      )
    ).to.be.revertedWith('LoanVault::prepareLoan:ERR_MIN_RAISE_ABOVE_DESIRED_RAISE_OR_MIN_RAISE_EQUALS_ZERO')
    
    await expect(
      LoanVault.prepareLoan(
        [1000, 1, 2592000, 100000000, 0, 0],
        BUNK_ADDRESS,
        BUNK_ADDRESS
      )
    ).to.be.revertedWith('LoanVault::prepareLoan:ERR_MIN_RAISE_ABOVE_DESIRED_RAISE_OR_MIN_RAISE_EQUALS_ZERO')

    await expect(
      LoanVault.prepareLoan(
        [1000, 1, 2592000, 100000001, 100000000, 0],
        BUNK_ADDRESS,
        BUNK_ADDRESS
      )
    ).to.be.revertedWith('LoanVault::prepareLoan:ERR_MIN_RAISE_ABOVE_DESIRED_RAISE_OR_MIN_RAISE_EQUALS_ZERO')

    await expect(
      LoanVault.prepareLoan(
        [1000, 1, 2592000, 100000000, 500000000, 0],
        BUNK_ADDRESS,
        BUNK_ADDRESS
      )
    ).to.be.revertedWith('LoanVault::prepareLoan:ERR_INVALID_REPAYMENT_CALCULATOR')

    // Temporarily set repaymentCalculator validity of address(0) to TRUE.
    await Globals.setRepaymentCalculatorValidity(BUNK_ADDRESS, true);
    
    await expect(
      LoanVault.prepareLoan(
        [1000, 1, 2592000, 100000000, 500000000, 0],
        BUNK_ADDRESS,
        BUNK_ADDRESS
      )
    ).to.be.revertedWith('LoanVault::prepareLoan:ERR_INVALID_PREMIUM_CALCULATOR')

    // Temporarily set premiumCalculator validity of BUNK_ADDRESS to TRUE.
    await Globals.setPremiumCalculatorValidity(BUNK_ADDRESS, true);

    await expect(
      LoanVault.prepareLoan(
        [1000, 1, 2592000, 100000000, 500000000, 0],
        BUNK_ADDRESS,
        BUNK_ADDRESS
      )
    )

    // Revert validity of BUNK_ADDRESS for repaymentCalculator AND premiumCalculator.
    await expect(Globals.setRepaymentCalculatorValidity(BUNK_ADDRESS, false));
    await expect(Globals.setPremiumCalculatorValidity(BUNK_ADDRESS, false));

  })

  it('prepareLoan() with valid input parameters', async function () {
    
    // TODO

  })


})
