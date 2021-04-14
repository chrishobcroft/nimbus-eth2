# beacon_chain
# Copyright (c) 2021 Status Research & Development GmbH
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at https://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at https://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# This file contains data types that are part of the spec and thus subject to
# serialization and spec updates.
#
# The spec folder in general contains code that has been hoisted from the
# specification and that follows the spec as closely as possible, so as to make
# it easy to keep up-to-date.
#
# These datatypes are used as specifications for serialization - thus should not
# be altered outside of what the spec says. Likewise, they should not be made
# `ref` - this can be achieved by wrapping them in higher-level
# types / composition

# TODO Careful, not nil analysis is broken / incomplete and the semantics will
#      likely change in future versions of the language:
#      https://github.com/nim-lang/RFCs/issues/250
{.experimental: "notnil".}

{.push raises: [Defect].}

import
  std/macros,
  stew/assign2,
  json_serialization/types as jsonTypes,
  ../../ssz/types as sszTypes, ../digest,
  nimcrypto/utils

const
  # https://github.com/ethereum/eth2.0-specs/blob/dev/specs/merge/beacon-chain.md#execution
  MAX_BYTES_PER_OPAQUE_TRANSACTION* = 1048576
  MAX_APPLICATION_TRANSACTIONS* = 16384
  BYTES_PER_LOGS_BLOOM* = 256

type
  # https://github.com/ethereum/eth2.0-specs/blob/eca6bd7d622a0cfb7343bff742da046ed25b3825/specs/merge/beacon-chain.md#custom-types
  OpaqueTransaction* = List[byte, MAX_BYTES_PER_OPAQUE_TRANSACTION]
  EthAddress* = object
    data*: array[20, byte]  # TODO there's a network_metadata type, but the import hierarchy's inconvenient without splitting out aspects of this module

  Eth1Transaction* = object
    nonce*: uint64
    gas_price*: Eth2Digest
    gas_limit*: uint64
    recipient*: EthAddress
    value*: Eth2Digest
    #input*: List[byte, MAX_BYTES_PER_OPAQUE_TRANSACTION]
    v*: Eth2Digest
    r*: Eth2Digest
    s*: Eth2Digest

  # https://github.com/ethereum/eth2.0-specs/blob/eca6bd7d622a0cfb7343bff742da046ed25b3825/specs/merge/beacon-chain.md#applicationpayload
  ApplicationPayload* = object
    block_hash*: Eth2Digest  # Hash of application block
    coinbase*: EthAddress
    state_root*: Eth2Digest
    gas_limit*: uint64
    gas_used*: uint64
    receipt_root*: Eth2Digest
    #logs_bloom*: array[BYTES_PER_LOGS_BLOOM, byte]
    transactions*: List[Eth1Transaction, MAX_APPLICATION_TRANSACTIONS]

  # https://github.com/ethereum/eth2.0-specs/blob/eca6bd7d622a0cfb7343bff742da046ed25b3825/specs/merge/beacon-chain.md#application-payload-processing
  ApplicationState* = object
    discard

  # https://github.com/ethereum/eth2.0-specs/blob/dev/specs/merge/validator.md#get_pow_chain_head
  PowBlock* = object
    discard

proc fromHex*(T: typedesc[EthAddress], s: string): T =
  hexToBytes(s, result)

proc writeValue*(w: var JsonWriter, a: EthAddress) {.raises: [Defect, IOError, SerializationError].} =
  w.writeValue $a

proc readValue*(r: var JsonReader, a: var EthAddress) {.raises: [Defect, IOError, SerializationError].} =
  try:
    a = fromHex(type(a), r.readValue(string))
  except ValueError:
    raiseUnexpectedValue(r, "Hex string expected")

# TODO move these elsewhere

# https://github.com/ethereum/eth2.0-specs/blob/dev/specs/merge/validator.md#get_pow_chain_head
func get_pow_chain_head(): PowBlock =
  discard

# https://github.com/ethereum/eth2.0-specs/blob/dev/specs/merge/validator.md#produce_application_payload
when false:
  func get_application_payload(state: BeaconState): ApplicationPayload =
    if not is_transition_completed(state):
      pow_block = get_pow_chain_head()
      if pow_block.total_difficulty < TRANSITION_TOTAL_DIFFICULTY:
        # Pre-merge, empty payload
        return ApplicationPayload()
      else:
        # Signify merge via last PoW block_hash and an otherwise empty payload
        return ApplicationPayload(block_hash=pow_block.block_hash)

    # Post-merge, normal payload
    application_parent_hash = state.application_block_hash
    produce_application_payload(state.application_block_hash)
