all       :; DAPP_SRC=contracts DAPP_BUILD_OPTIMIZE=1 DAPP_BUILD_OPTIMIZE_RUNS=200 dapp --use solc:0.6.11 build
clean     :; dapp clean
test      :; ./test.sh
ci-test   :; ./test-ci.sh
