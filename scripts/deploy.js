const fs = require('fs')
const chalk = require('chalk')
const { config, ethers } = require('hardhat')
const { utils } = require('ethers')

const governor = '0xc783df8a850f42e7F7e57013759C285caa701eB6'

async function main () {
  console.log('📡 Deploy \n')

  const mapleToken = await deploy('MapleToken', ['Maple FDT', 'MPL', governor])
  console.log(mapleToken.address)

  const mapleGlobals = await deploy('MapleGlobals', [
    governor,
    mapleToken.address
  ])
  console.log(mapleGlobals.address)

  const LPStakeLockerFactory = await deploy('LPStakeLockerFactory')
  console.log(LPStakeLockerFactory.address)

  const LPFactory = await deploy('LPFactory')
  console.log(LPFactory.address)

  // auto deploy to read contract directory and deploy them all (add ".args" files for arguments)
  // await autoDeploy()

  // const yourContract = await deploy('YourContract')
  // console.log(yourContract.address)

  // const mintableTokenUSDC = await deploy('MintableTokenUSDC', [
  //   'Stablecoin USDC',
  //   'USDC',
  //   6,
  // ])
  // console.log(mintableTokenUSDC.address)

  // const mintableTokenDAI = await deploy('MintableTokenDAI', [
  //   'Stablecoin DAI',
  //   'DAI',
  //   18,
  // ])
  // console.log(mintableTokenDAI.address)

  // const mintableTokenWBTC = await deploy('MintableTokenWBTC', [
  //   'Wrapped BTC',
  //   'wBTC',
  //   8,
  // ])
  // console.log(mintableTokenWBTC.address)

  // const mapleToken = await deploy('mapleToken', [
  //   'Maple FDT',
  //   'MPL',
  //   mintableTokenDAI.address,
  // ])
  // console.log(mapleToken.address)

  // // 2) Deploy the MapleGlobal contract, using MapleToken address as input.
  // const mapleGlobal = await deploy('MapleGlobal', [
  //   governor,
  //   mapleToken.address,
  // ])
  // console.log(mapleGlobal.address)

  // const liquidityPoolFactory = await deploy('LiquidityPoolFactory')

  // const bFactory = await deploy('BFactory')
  // console.log(bFactory.address)

  // const bCreator = await deploy('BCreator', [bFactory.address])
  // console.log(bCreator.address)

  // const bPool = await deploy('BPool')
  // console.log(bPool.address)

  // OR
  // custom deploy (to use deployed addresses dynamically for example:)
  // const exampleToken = await deploy("ExampleToken")
  // const examplePriceOracle = await deploy("ExamplePriceOracle")
  // const smartContractWallet = await deploy("SmartContractWallet",[exampleToken.address,examplePriceOracle.address])
}

async function deploy (name, _args) {
  try {
    const args = _args || []

    console.log(` 🛰  Deploying ${name}`)
    const contractArtifacts = await ethers.getContractFactory(name)
    const contract = await contractArtifacts.deploy(...args)
    console.log(
      ' 📄',
      chalk.cyan(name),
      'deployed to:',
      chalk.magenta(contract.address),
      '\n'
    )
    fs.writeFileSync(`artifacts/${name}.address`, contract.address)
    console.log(
      '💾  Artifacts (address, abi, and args) saved to: ',
      chalk.blue('packages/buidler/artifacts/'),
      '\n'
    )
    return contract
  } catch (err) {}
}

const isSolidity = fileName =>
  fileName.indexOf('.sol') >= 0 && fileName.indexOf('.swp.') < 0

function readArgumentsFile (contractName) {
  let args = []
  try {
    const argsFile = `./contracts/${contractName}.args`
    if (fs.existsSync(argsFile)) {
      args = JSON.parse(fs.readFileSync(argsFile))
    }
  } catch (e) {
    console.log(e)
  }

  return args
}

async function autoDeploy () {
  const contractList = fs.readdirSync(config.paths.sources)
  return contractList
    .filter(fileName => isSolidity(fileName))
    .reduce((lastDeployment, fileName) => {
      const contractName = fileName.replace('.sol', '')
      const args = readArgumentsFile(contractName)

      // Wait for last deployment to complete before starting the next
      return lastDeployment.then(resultArrSoFar =>
        deploy(contractName, args).then((result, b, c) => {
          if (args && result && result.interface && result.interface.deploy) {
            let encoded = utils.defaultAbiCoder.encode(
              result.interface.deploy.inputs,
              args
            )
            fs.writeFileSync(`artifacts/${contractName}.args`, encoded)
          }

          return [...resultArrSoFar, result]
        })
      )
    }, Promise.resolve([]))
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error)
    process.exit(1)
  })
