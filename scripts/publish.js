const fs = require('fs')
const chalk = require('chalk')
const bre = require('hardhat')
const { FixedNumber } = require('ethers')

const publishDir = '../react-app/src/contracts'

async function publishContract(contractName) {
  const addressLocation = `${bre.config.paths.artifacts}/${contractName}.address`
  const abiLocation = `${bre.config.paths.artifacts}/contracts/${contractName}.sol/${contractName}.json`
  const publishAddressLocation = `${publishDir}/${contractName}.address.js`
  const publishAbiLocation = `${publishDir}/${contractName}.abi.js`
  const publishByteCodeLocation = `${publishDir}/${contractName}.bytecode.js`

  console.log(
    'Publishing',
    chalk.cyan(contractName),
    'to',
    chalk.yellow(publishDir),
  )

  let contract = JSON.parse(fs.readFileSync(abiLocation).toString())

  if (fs.readFileSync(addressLocation)) {
    const address = await fs.readFileSync(addressLocation).toString()
    fs.writeFileSync(publishAddressLocation, `module.exports = "${address}";`)
  }

  fs.writeFileSync(
    publishAbiLocation,
    `module.exports = ${JSON.stringify(contract.abi, null, 2)};`,
  )
  fs.writeFileSync(
    publishByteCodeLocation,
    `module.exports = "${contract.bytecode}";`,
  )

  return true
}

async function main() {
  try {
    if (!fs.existsSync(publishDir)) {
      fs.mkdirSync(publishDir)
    }
    const finalContractList = []
    fs.readdirSync(bre.config.paths.sources).forEach((file) => {
      if (file.indexOf('.sol') >= 0) {
        const contractName = file.replace('.sol', '')
        // Add contract to list if publishing is successful
        if (publishContract(contractName)) {
          finalContractList.push(contractName)
        }
      }
    })
    fs.writeFileSync(
      `${publishDir}/contracts.js`,
      `module.exports = ${JSON.stringify(finalContractList)};`,
    )
  } catch (err) {
    console.log(err)
  }
}
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })
