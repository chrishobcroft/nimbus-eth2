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
  # https://github.com/ethereum/eth2.0-specs/blob/dev/specs/merge/beacon-chain.md#execution
  MAX_BYTES_PER_OPAQUE_TRANSACTION* = 1048576
  MAX_APPLICATION_TRANSACTIONS* = 16384
  BYTES_PER_LOGS_BLOOM* = 256

  EVM_BLOCK_ROOTS_SIZE* = 8

type
  # https://github.com/ethereum/eth2.0-specs/blob/eca6bd7d622a0cfb7343bff742da046ed25b3825/specs/merge/beacon-chain.md#custom-types
  OpaqueTransaction* = List[byte, MAX_BYTES_PER_OPAQUE_TRANSACTION]
  EthAddress* = object
    data*: array[20, byte]  # TODO there's a network_metadata type, but the import hierarchy's inconvenient without splitting out aspects of this module

  BloomLogs* = object
    data*: array[BYTES_PER_LOGS_BLOOM, byte]

  Eth1TransactionInput* = object
    data*: List[byte, MAX_BYTES_PER_OPAQUE_TRANSACTION]

  # TODO check against catalyst-for-rayonism branch
  Eth1Transaction* = object
    nonce*: uint64
    gas_price*: Eth2Digest
    gas_limit*: uint64
    recipient*: EthAddress
    value*: Eth2Digest
    input*: Eth1TransactionInput
    v*: Eth2Digest
    r*: Eth2Digest
    s*: Eth2Digest

  BeaconChainData* = object
    slot*: uint64 # TODO Slot, but dependency issue wrt this/base
    randao_mix*: Eth2Digest
    timestamp*: uint64
    recent_block_roots*: array[EVM_BLOCK_ROOTS_SIZE, Eth2Digest]

  # https://github.com/gballet/go-ethereum/blob/7eea1cff4121d23ab4c8932ef33ff9b077a20da1/eth/catalyst/api_test.go#L151-L163
  ApplicationPayload* = object
    parentHash*: Eth2Digest
    miner*: EthAddress
    stateRoot*: Eth2Digest
    gasLimit*: uint64
    gasUsed*: uint64
    transactions*: List[Eth1Transaction, MAX_APPLICATION_TRANSACTIONS]
    receiptRoot*: Eth2Digest
    blockHash*: Eth2Digest
    timestamp*: uint64
    number*: uint64

  # https://github.com/gballet/go-ethereum/blob/7eea1cff4121d23ab4c8932ef33ff9b077a20da1/eth/catalyst/api_test.go#L130-L133
  BlockParams* = object
    parentHash*: Eth2Digest
    timestamp*: uint64

  # https://github.com/ethereum/eth2.0-specs/blob/eca6bd7d622a0cfb7343bff742da046ed25b3825/specs/merge/beacon-chain.md#application-payload-processing
  ApplicationState* = object
    discard

  # https://github.com/ethereum/eth2.0-specs/blob/dev/specs/merge/validator.md#get_pow_chain_head
  PowBlock* = object
    discard

proc fromHex*(T: typedesc[EthAddress], s: string): T =
  hexToBytes(s, result.data)

proc writeValue*(w: var JsonWriter, a: EthAddress) {.raises: [Defect, IOError, SerializationError].} =
  w.writeValue $a

proc readValue*(r: var JsonReader, a: var EthAddress) {.raises: [Defect, IOError, SerializationError].} =
  try:
    a = fromHex(type(a), r.readValue(string))
  except ValueError:
    raiseUnexpectedValue(r, "Hex string expected")
