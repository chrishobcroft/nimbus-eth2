## This module contains signatures for the Ethereum merge RPCs.
## The signatures are not imported directly, but read and processed with parseStmt,
## then a procedure body is generated to marshal native Nim parameters to json and visa versa.

# https://github.com/status-im/nim-web3/blob/master/web3/ethcallsigs.nim

import json, options, stint, ethtypes

# https://hackmd.io/@n0ble/ethereum_consensus_upgrade_mainnet_perspective
# https://github.com/gballet/go-ethereum/blob/catalyst-for-rayonism/eth/catalyst/api.go
# https://github.com/gballet/go-ethereum/blob/catalyst-for-rayonism/eth/catalyst/api_test.go
proc consensus_AssembleBlock(blockParams: BlockParams): ApplicationPayload

# basic flow appears to be consensus_NewBlock(consensus_AssembleBlock())
proc consensus_NewBlock(executableData: ApplicationPayload): bool

# "FinalizeBlock is called to mark a block as synchronized, so that data that
# is no longer needed can be removed." Optional at first, and takes data from
# what consensus_AssembleBlock() alredy takes.
proc consensus_FinalizeBlock(blockHash: Eth2Digest): bool

proc consensus_SetHead(newHead: Eth2Digest): bool
