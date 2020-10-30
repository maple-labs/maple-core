const fs = require('fs')
const chalk = require('chalk')
const bre = require('hardhat')

const directories = ['../react-app/src/contracts', '../contracts/src/contracts']

function publishContract(contractName, directory) {
  console.log(
    'Publishing',
    chalk.cyan(contractName),
    'to',
    chalk.yellow(directory),
  )
  let contract = fs
    .readFileSync(
      `${bre.config.paths.artifacts}/contracts/${contractName}.sol/${contractName}.json`,
    )
    .toString()
  const address = fs
    .readFileSync(`${bre.config.paths.artifacts}/${contractName}.address`)
    .toString()
  contract = JSON.parse(contract)
  fs.writeFileSync(
    `${directory}/${contractName}.address.js`,
    `module.exports = "${address}";`,
  )
  fs.writeFileSync(
    `${directory}/${contractName}.abi.js`,
    `module.exports = ${JSON.stringify(contract.abi, null, 2)};`,
  )
  fs.writeFileSync(
    `${directory}/${contractName}.bytecode.js`,
    `module.exports = "${contract.bytecode}";`,
  )

  return true
}

async function main() {

  for (let i = 0; i < directories.length; i++) {
    if (!fs.existsSync(directories[i])) {
      fs.mkdirSync(directories[i])
    }
    const finalContractList = []
    fs.readdirSync(bre.config.paths.sources).forEach((file) => {
      if (file.indexOf('.sol') >= 0) {
        const contractName = file.replace('.sol', '')
        // Add contract to list if publishing is successful
        try {
          if (publishContract(contractName, directories[i])) {
            finalContractList.push(contractName)
          }
        }
        catch(e) {
          // console.log(e)
        }
      }
    })
    fs.writeFileSync(
      `${directories[i]}/contracts.js`,
      `module.exports = ${JSON.stringify(finalContractList)};`,
    )
  }
  
}
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })
