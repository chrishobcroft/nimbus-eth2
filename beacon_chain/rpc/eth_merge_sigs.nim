## This module contains signatures for the Ethereum merge RPCs.
## The signatures are not imported directly, but read and processed with parseStmt,
## then a procedure body is generated to marshal native Nim parameters to json and visa versa.

# https://github.com/status-im/nim-web3/blob/master/web3/ethcallsigs.nim

import json, options, stint, ethtypes

# https://hackmd.io/@n0ble/ethereum_consensus_upgrade_mainnet_perspective
# https://github.com/gballet/go-ethereum/blob/catalyst-for-rayonism/eth/catalyst/api.go
# https://github.com/gballet/go-ethereum/blob/catalyst-for-rayonism/eth/catalyst/api_test.go
proc consensus_AssembleBlock(): bool
proc consensus_NewBlock(executableData: ExecutableData): bool
proc consensus_FinalizeBlock(blockHash: Eth2Digest): bool

# proc consensus_SetHead(): bool    # not tested in catalyst-for-rayonism branch
# and presumably renamed NewHead

# https://github.com/gballet/go-ethereum/tree/catalyst-for-executable-beacon-chain
# proc ProduceBlock()
