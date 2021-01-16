const { getMapleArtifacts } = require("./get-artifacts");

const network = process.argv[2];
const version = process.argv[3];

getMapleArtifacts(network, version);
