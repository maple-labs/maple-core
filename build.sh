#!/usr/bin/env bash
set -e

export DAPP_BUILD_OPTIMIZE=1
export DAPP_BUILD_OPTIMIZE_RUNS=200
export DAPP_SOLC_VERSION=0.6.11
export DAPP_SRC="contracts"
export DAPP_REMAPPINGS=$(cat remappings.txt)
export DAPP_LINK_TEST_LIBRARIES=1

LANG=C.UTF-8 dapp --optimize --optimize-runs 200 --verbose build
