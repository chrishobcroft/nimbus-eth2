#!/usr/bin/env bash
# set -Eeuo pipwfail
# https://github.com/prysmaticlabs/bazel-go-ethereum/blob/catalyst/run-catalyst.sh

# To increase verbosity: debug.verbosity(5) or debug.verbosity(6)

echo \{ \
  \"config\": \{ \
    \"chainId\": 220720, \
    \"homesteadBlock\": 0, \
    \"eip150Block\": 0, \
    \"eip155Block\": 0, \
    \"eip158Block\": 0, \
    \"byzantiumBlock\": 0, \
    \"constantinopleBlock\": 0, \
    \"petersburgBlock\": 0, \
    \"istanbulBlock\": 0, \
    \"catalystBlock\": 0 \
  \}, \
  \"alloc\": \{\}, \
  \"coinbase\": \"0x0000000000000000000000000000000000000000\", \
  \"difficulty\": \"0x20000\", \
  \"extraData\": \"\", \
  \"gasLimit\": \"0x2fefd8\", \
  \"nonce\": \"0x0000000000220720\", \
  \"mixhash\": \"0x0000000000000000000000000000000000000000000000000000000000000000\", \
  \"parentHash\": \"0x0000000000000000000000000000000000000000000000000000000000000000\", \
  \"timestamp\": \"0x00\" \
\} > /tmp/catalystgenesis.json

# TODO these paths need to be generalized
rm /tmp/catalystchaindata -rvf
~/clients/catalyst/build/bin/catalyst --catalyst --datadir /tmp/catalystchaindata init /tmp/catalystgenesis.json
~/clients/catalyst/build/bin/catalyst --catalyst --rpc --rpcapi net,eth,eth2,consensus,catalyst --nodiscover --miner.etherbase 0x1000000000000000000000000000000000000000 --datadir /tmp/catalystchaindata console
