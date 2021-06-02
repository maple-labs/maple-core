const fs = require('fs');
const crypto = require('crypto');

const { contracts } = require('./out/dapp.sol.json');

const ignorePaths = ['/test/', '/external-interfaces/', 'lib/', 'module/'];
const pathIgnored = (path) => ignorePaths.reduce((ignore, ignorePath) => path.includes(ignorePath) || ignore, false);
const contractPaths = Object.keys(contracts).filter((path) => !pathIgnored(path));

const spliceOut = (code, index, length) => code.slice(0, index) + code.slice(index + length);
const spliceOutSwarm = (code) => spliceOut(code, code.length - 86, 64);
const spliceOutAddress = (code) => spliceOut(code, 2, 40);

const normalizeDeployedBytecode = (code) => spliceOutSwarm(code.startsWith('73') ? spliceOutAddress(code) : code);

const stripLibRefs = (code, index = code.indexOf('__$')) => index >= 0 ? stripLibRefs(spliceOut(code, index, 40)) : code;

const hash = (text) => '0x' + crypto.createHash('sha256').update(Buffer.from(text, 'utf8')).digest('hex');

const metadata = contractPaths.map((path) => {
  const contractName = Object.keys(contracts[path])[0];
  const { sources } = JSON.parse(contracts[path][contractName].metadata);
  const { keccak256: sourceHash } = sources[path];
  const { deployedBytecode } = contracts[path][contractName].evm;
  const contractSize = deployedBytecode.object.length / 2;
  const normalizedDeployedBytecode = normalizeDeployedBytecode(deployedBytecode.object);
  const bytecodeHashWithLibRefs = hash(normalizedDeployedBytecode);
  const bytecodeHashWithoutLibRefs = hash(stripLibRefs(normalizedDeployedBytecode));
  
  return { contractName, contractSize, sourceHash, bytecodeHashWithLibRefs, bytecodeHashWithoutLibRefs, rawBytecode: deployedBytecode.object };
});

metadata.sort(({ contractName: contractNameA }, { contractName: contractNameB }) => contractNameA.localeCompare(contractNameB));

fs.writeFileSync('./metadata.json', JSON.stringify(metadata, null, ' ').concat('\n'));
