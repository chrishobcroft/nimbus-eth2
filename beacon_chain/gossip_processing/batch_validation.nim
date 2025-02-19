# beacon_chain
# Copyright (c) 2019-2021 Status Research & Development GmbH
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Status
  chronicles, chronos,
  stew/results,
  eth/keys,
  # Internals
  ../spec/[
    datatypes, crypto, digest, helpers, signatures_batch],
  ../consensus_object_pools/[
    blockchain_dag, block_quarantine,
    attestation_pool, exit_pool,
    block_pools_types, spec_cache
  ],
  ".."/[beacon_node_types, ssz, beacon_clock]

export BrHmacDrbgContext

logScope:
  topics = "gossip_checks"

# Batched gossip validation
# ----------------------------------------------------------------
{.push raises: [Defect].}

type
  BatchCrypto* = object
    # The buffers are bounded by BatchedCryptoSize (16) which was chosen:
    # - based on "nimble bench" in nim-blscurve
    #   so that low power devices like Raspberry Pi 4 can process
    #   that many batched verifications within 20ms
    # - based on the accumulation rate of attestations and aggregates
    #   in large instances which were 12000 per slot (12s)
    #   hence 1 per ms (but the pattern is bursty around the 4s mark)
    pendingBuffer: seq[SignatureSet]
    resultsBuffer: seq[Future[Result[void, cstring]]]
    sigVerifCache: BatchedBLSVerifierCache ##\
    ## A cache for batch BLS signature verification contexts
    rng: ref BrHmacDrbgContext  ##\
    ## A reference to the Nimbus application-wide RNG

const
  # We cap waiting for an idle slot in case there's a lot of network traffic
  # taking up all CPU - we don't want to _completely_ stop processing blocks
  # in this case (attestations will get dropped) - doing so also allows us
  # to benefit from more batching / larger network reads when under load.
  BatchAttAccumTime = 10.milliseconds

  # Threshold for immediate trigger of batch verification.
  # A balance between throughput and worst case latency.
  # At least 6 so that the constant factors
  # (RNG for blinding and Final Exponentiation)
  # are amortized,
  # but not too big as we need to redo checks one-by-one if one failed.
  BatchedCryptoSize = 16

proc new*(T: type BatchCrypto, rng: ref BrHmacDrbgContext): ref BatchCrypto =
  (ref BatchCrypto)(rng: rng)

func clear(batchCrypto: var BatchCrypto) =
  ## Empty the crypto-pending attestations & aggregate queues
  batchCrypto.pendingBuffer.setLen(0)
  batchCrypto.resultsBuffer.setLen(0)

proc done(batchCrypto: var BatchCrypto, idx: int) =
  ## Send signal to [Attestation/Aggregate]Validator
  ## that the attestation was crypto-verified (and so gossip validated)
  ## with success
  batchCrypto.resultsBuffer[idx].complete(Result[void, cstring].ok())

proc fail(batchCrypto: var BatchCrypto, idx: int, error: cstring) =
  ## Send signal to [Attestation/Aggregate]Validator
  ## that the attestation was NOT crypto-verified (and so NOT gossip validated)
  batchCrypto.resultsBuffer[idx].complete(Result[void, cstring].err(error))

proc complete(batchCrypto: var BatchCrypto, idx: int, res: Result[void, cstring]) =
  ## Send signal to [Attestation/Aggregate]Validator
  batchCrypto.resultsBuffer[idx].complete(res)

proc processBufferedCrypto(self: var BatchCrypto) =
  ## Drain all attestations waiting for crypto verifications

  doAssert self.pendingBuffer.len ==
             self.resultsBuffer.len

  if self.pendingBuffer.len == 0:
    return

  trace "batch crypto - starting",
    batchSize = self.pendingBuffer.len

  let startTime = Moment.now()

  var secureRandomBytes: array[32, byte]
  self.rng[].brHmacDrbgGenerate(secureRandomBytes)

  # TODO: For now only enable serial batch verification
  let ok = batchVerifySerial(
    self.sigVerifCache,
    self.pendingBuffer,
    secureRandomBytes)

  let stopTime = Moment.now()

  debug "batch crypto - finished",
    batchSize = self.pendingBuffer.len,
    cryptoVerified = ok,
    dur = stopTime - startTime

  if ok:
    for i in 0 ..< self.resultsBuffer.len:
      self.done(i)
  else:
    debug "batch crypto - failure, falling back",
      batchSize = self.pendingBuffer.len
    for i in 0 ..< self.pendingBuffer.len:
      let ok = blsVerify self.pendingBuffer[i]
      if ok:
        self.done(i)
      else:
        self.fail(i, "batch crypto verification: invalid signature")

  self.clear()

proc deferCryptoProcessing(self: ref BatchCrypto, idleTimeout: Duration) {.async.} =
  ## Process pending crypto check:
  ## - if time threshold is reached
  ## - or if networking is idle

  # TODO: how to cancel the scheduled `deferCryptoProcessing(BatchAttAccumTime)` ?
  #       when the buffer size threshold is reached?
  # In practice this only happens when we receive a burst of attestations/aggregates.
  # Though it's possible to reach the threshold 9ms in,
  # and have only 1ms left for further accumulation.
  await sleepAsync(idleTimeout)
  self[].processBufferedCrypto()

proc schedule(batchCrypto: ref BatchCrypto, fut: Future[Result[void, cstring]], checkThreshold = true) =
  ## Schedule a cryptocheck for processing
  ##
  ## The buffer is processed:
  ## - when 16 or more attestations/aggregates are buffered (BatchedCryptoSize)
  ## - when there are no network events (idleAsync)
  ## - otherwise after 10ms (BatchAttAccumTime)

  # Note: use the resultsBuffer size to detect the first item
  #       as pendingBuffer is appended to 3 by 3 in case of aggregates

  batchCrypto.resultsBuffer.add fut

  if batchCrypto.resultsBuffer.len == 1:
    # First attestation to be scheduled in the batch
    # wait for an idle time or up to 10ms before processing
    trace "batch crypto - scheduling next",
      deadline = BatchAttAccumTime
    asyncSpawn batchCrypto.deferCryptoProcessing(BatchAttAccumTime)
  elif checkThreshold and
       batchCrypto.resultsBuffer.len >= BatchedCryptoSize:
    # Reached the max buffer size, process immediately
    # TODO: how to cancel the scheduled `deferCryptoProcessing(BatchAttAccumTime)` ?
    batchCrypto[].processBufferedCrypto()

proc scheduleAttestationCheck*(
      batchCrypto: ref BatchCrypto,
      fork: Fork, genesis_validators_root: Eth2Digest,
      epochRef: EpochRef,
      attestation: Attestation
     ): Option[(Future[Result[void, cstring]], CookedSig)] =
  ## Schedule crypto verification of an attestation
  ##
  ## The buffer is processed:
  ## - when 16 or more attestations/aggregates are buffered (BatchedCryptoSize)
  ## - when there are no network events (idleAsync)
  ## - otherwise after 10ms (BatchAttAccumTime)
  ##
  ## This returns None if crypto sanity checks failed
  ## and a future with the deferred attestation check otherwise.
  doAssert batchCrypto.pendingBuffer.len < BatchedCryptoSize

  let (sanity, sig) = batchCrypto
                       .pendingBuffer
                       .addAttestation(
                         fork, genesis_validators_root, epochRef,
                         attestation
                       )
  if not sanity:
    return none((Future[Result[void, cstring]], CookedSig))

  let fut = newFuture[Result[void, cstring]](
    "batch_validation.scheduleAttestationCheck"
  )

  batchCrypto.schedule(fut)

  return some((fut, sig))

proc scheduleAggregateChecks*(
      batchCrypto: ref BatchCrypto,
      fork: Fork, genesis_validators_root: Eth2Digest,
      epochRef: EpochRef,
      signedAggregateAndProof: SignedAggregateAndProof
     ): Option[(
       tuple[slotCheck, aggregatorCheck, aggregateCheck:
         Future[Result[void, cstring]]],
       CookedSig)] =
  ## Schedule crypto verification of an aggregate
  ##
  ## This involves 3 checks:
  ## - verify_slot_signature
  ## - verify_aggregate_and_proof_signature
  ## - is_valid_indexed_attestation
  ##
  ## The buffer is processed:
  ## - when 16 or more attestations/aggregates are buffered (BatchedCryptoSize)
  ## - when there are no network events (idleAsync)
  ## - otherwise after 10ms (BatchAttAccumTime)
  ##
  ## This returns None if crypto sanity checks failed
  ## and 2 futures with the deferred aggregate checks otherwise.
  doAssert batchCrypto.pendingBuffer.len < BatchedCryptoSize

  template aggregate_and_proof: untyped = signedAggregateAndProof.message
  template aggregate: untyped = aggregate_and_proof.aggregate

  type R = (
    tuple[slotCheck, aggregatorCheck, aggregateCheck:
      Future[Result[void, cstring]]],
    CookedSig)

  # Enqueue in the buffer
  # ------------------------------------------------------
  let aggregator = epochRef.validator_keys[aggregate_and_proof.aggregator_index]
  block:
    let sanity = batchCrypto
                  .pendingBuffer
                  .addSlotSignature(
                    fork, genesis_validators_root,
                    aggregate.data.slot,
                    aggregator,
                    aggregate_and_proof.selection_proof
                  )
    if not sanity:
      return none(R)

  block:
    let sanity = batchCrypto
                  .pendingBuffer
                  .addAggregateAndProofSignature(
                    fork, genesis_validators_root,
                    aggregate_and_proof,
                    aggregator,
                    signed_aggregate_and_proof.signature
                  )
    if not sanity:
      return none(R)

  let (sanity, sig) = batchCrypto
                       .pendingBuffer
                       .addAttestation(
                         fork, genesis_validators_root, epochRef,
                         aggregate
                       )
  if not sanity:
    return none(R)

  let futSlot = newFuture[Result[void, cstring]](
    "batch_validation.scheduleAggregateChecks.slotCheck"
  )
  let futAggregator = newFuture[Result[void, cstring]](
    "batch_validation.scheduleAggregateChecks.aggregatorCheck"
  )

  let futAggregate = newFuture[Result[void, cstring]](
    "batch_validation.scheduleAggregateChecks.aggregateCheck"
  )

  batchCrypto.schedule(futSlot, checkThreshold = false)
  batchCrypto.schedule(futAggregator, checkThreshold = false)
  batchCrypto.schedule(futAggregate)

  return some(((futSlot, futAggregator, futAggregate), sig))
