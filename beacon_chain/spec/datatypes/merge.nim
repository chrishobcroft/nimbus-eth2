# beacon_chain
# Copyright (c) 2021 Status Research & Development GmbH
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at https://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at https://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# TODO Careful, not nil analysis is broken / incomplete and the semantics will
#      likely change in future versions of the language:
#      https://github.com/nim-lang/RFCs/issues/250
{.experimental: "notnil".}

{.push raises: [Defect].}

import
  std/macros,
  stew/assign2,
  json_serialization,
  json_serialization/types as jsonTypes,
  ../../ssz/types as sszTypes, ../digest,
  nimcrypto/utils

const
  # https://github.com/ethereum/eth2.0-specs/blob/e895c29f3f42382a0c913f3d0fd33522d7db9e87/specs/merge/beacon-chain.md#execution
  MAX_BYTES_PER_OPAQUE_TRANSACTION* = 1048576
  MAX_EXECUTION_TRANSACTIONS* = 16384
  BYTES_PER_LOGS_BLOOM* = 256

  EVM_BLOCK_ROOTS_SIZE* = 8

type
  # https://github.com/ethereum/eth2.0-specs/blob/eca6bd7d622a0cfb7343bff742da046ed25b3825/specs/merge/beacon-chain.md#custom-types
  # TODO is this maneuver sizeof()/memcpy()/SSZ-equivalent? Pretty sure, but not 100% certain
  OpaqueTransaction* = object
    data*: List[byte, MAX_BYTES_PER_OPAQUE_TRANSACTION]

  EthAddress* = object
    data*: array[20, byte]  # TODO there's a network_metadata type, but the import hierarchy's inconvenient without splitting out aspects of this module

  BloomLogs* = object
    data*: array[BYTES_PER_LOGS_BLOOM, byte]

  # https://github.com/ethereum/eth2.0-specs/blob/dev/specs/merge/beacon-chain.md#executionpayload
  ExecutionPayload* = object
    block_hash*: Eth2Digest  # Hash of execution block
    parent_hash*: Eth2Digest
    coinbase*: EthAddress
    state_root*: Eth2Digest
    number*: uint64
    gas_limit*: uint64
    gas_used*: uint64
    timestamp*: uint64
    receipt_root*: Eth2Digest
    logs_bloom*: BloomLogs
    transactions*: List[OpaqueTransaction, MAX_EXECUTION_TRANSACTIONS]

  # https://github.com/gballet/go-ethereum/blob/7eea1cff4121d23ab4c8932ef33ff9b077a20da1/eth/catalyst/api_test.go#L130-L133
  BlockParams* = object
    parentHash*: Eth2Digest
    timestamp*: string

proc fromHex*(T: typedesc[EthAddress], s: string): T =
  hexToBytes(s, result.data)

proc writeValue*(w: var JsonWriter, a: EthAddress) {.raises: [Defect, IOError, SerializationError].} =
  w.writeValue $a

proc readValue*(r: var JsonReader, a: var EthAddress) {.raises: [Defect, IOError, SerializationError].} =
  try:
    a = fromHex(type(a), r.readValue(string))
  except ValueError:
    raiseUnexpectedValue(r, "Hex string expected")
