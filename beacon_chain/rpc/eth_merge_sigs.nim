## This module contains signatures for the Ethereum merge RPCs.
## The signatures are not imported directly, but read and processed with parseStmt,
## then a procedure body is generated to marshal native Nim parameters to json and visa versa.

# https://github.com/status-im/nim-web3/blob/master/web3/ethcallsigs.nim

import json, options, stint, ethtypes

# https://hackmd.io/@n0ble/ethereum_consensus_upgrade_mainnet_perspective
# https://github.com/gballet/go-ethereum/blob/catalyst-for-rayonism/eth/catalyst/api.go
# https://github.com/gballet/go-ethereum/blob/catalyst-for-rayonism/eth/catalyst/api_test.go
proc consensus_assembleBlock(blockParams: BlockParams): ApplicationPayload

# TODO from the Catalyst side these don't seem to be exactly bools

# basic flow appears to be consensus_NewBlock(consensus_AssembleBlock())
# where tx pool is maintained by eth1 client and effectively accessed by
# consensus_AssembleBlock(), which returns a value which is treatable as
# a black box (ApplicationPayload is just conceptually an opaque type in
# the view of the consensus layer).
proc consensus_newBlock(executableData: ApplicationPayload): bool

# "FinalizeBlock is called to mark a block as synchronized, so that data that
# is no longer needed can be removed." Optional at first, and takes data from
# what consensus_AssembleBlock() alredy takes.
proc consensus_finalizeBlock(blockHash: Eth2Digest): bool

# call this in updateHead()
proc consensus_setHead(newHead: Eth2Digest): bool
