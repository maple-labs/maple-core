const fs = require('fs')
const chalk = require('chalk')
const { config, ethers } = require('hardhat')
const { utils } = require('ethers')

const mintableUSDC = require('../../contracts/src/contracts/MintableTokenUSDC.address.js')
const uniswapRouter = require('../../contracts/src/contracts/UniswapV2Router02.address.js')
const governor = '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266'

async function main () {
  console.log('📡 Deploy \n')

  const mapleToken = await deploy('MapleToken', [
    'MapleToken',
    'MPL',
    mintableUSDC
  ])
  console.log(mapleToken.address)

  const accounts = await ethers.provider.listAccounts()
  console.log(accounts[0])

  const mapleGlobals = await deploy('MapleGlobals', [
    governor,
    mapleToken.address
  ])
  console.log(mapleGlobals.address)

  const LPStakeLockerFactory = await deploy('LPStakeLockerFactory')
  console.log(LPStakeLockerFactory.address)

  const liquidAssetLockerFactory = await deploy('LiquidAssetLockerFactory')
  console.log(liquidAssetLockerFactory.address)

  const LPFactory = await deploy('LPFactory')
  console.log(LPFactory.address)

  const mapleTreasury = await deploy('MapleTreasury', [
    mapleToken.address,
    mintableUSDC,
    uniswapRouter,
    mapleGlobals.address
  ])
  console.log(mapleTreasury.address)
  const updateGlobals = await mapleGlobals.setMapleTreasury(mapleTreasury.address)
  
  const LVFactory = await deploy('LoanVaultFactory')
  console.log(LVFactory.address)

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
