#!/usr/bin/env bash
set -e

[[ $SKIP_MAINNET_CHECK || "$ETH_RPC_URL" && "$(seth chain)" == "ethlive" ]] || { echo "Please set a mainnet ETH_RPC_URL"; exit 1; }

export DAPP_TEST_TIMESTAMP=1615792486
export DAPP_TEST_NUMBER=12045000
export DAPP_SOLC_VERSION=0.6.11
export DAPP_SRC="contracts"
export DAPP_BUILD_OPTIMIZE=1
export DAPP_BUILD_OPTIMIZE_RUNS=200
export DAPP_LINK_TEST_LIBRARIES=1

if [ ${1} ]; then match=${1}; dapp_test_verbosity=2; else match="contracts/test"; dapp_test_verbosity=1; fi

LANG=C.UTF-8 dapp test --match "$match" --rpc-url "$ETH_RPC_URL" --verbosity $dapp_test_verbosity --cache "cache/dapp-cache" --fuzz-runs 1000
