#!/usr/bin/env bash
set -e

export DAPP_SOLC_VERSION=0.6.11
export DAPP_SRC="contracts"
export DAPP_BUILD_OPTIMIZE=1
export DAPP_BUILD_OPTIMIZE_RUNS=200
export DAPP_LINK_TEST_LIBRARIES=0
export DAPP_REMAPPINGS=$(cat remappings)

dapp --use solc:0.6.11 build
