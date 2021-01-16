const { deploy } = require("@maplelabs/hardhat-scripts");
const { getArtifacts, DEPS, CORE } = require("./artifacts");

async function main() {
  const USDC = getArtifacts(DEPS.USDC);
  await deploy(CORE.MapleToken, [CORE.MapleToken, "MPL", USDC.address]);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
