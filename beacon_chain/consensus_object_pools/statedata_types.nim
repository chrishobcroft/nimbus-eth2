import
  stew/assign2,
  # Internals
  ../spec/[datatypes/phase0, datatypes/altair, digest]

type
  BlockRef* = ref object
    ## Node in object graph guaranteed to lead back to tail block, and to have
    ## a corresponding entry in database.
    ## Block graph should form a tree - in particular, there are no cycles.

    root*: Eth2Digest ##\
    ## Root that can be used to retrieve block data from database

    parent*: BlockRef ##\
    ## Not nil, except for the tail

    slot*: Slot # could calculate this by walking to root, but..

  StateKind = enum
    skPhase0,
    skAltair

  StateData* = object
    # TODO remove field
    data*: phase0.HashedBeaconState

    case kind: StateKind
    of skPhase0: phase0HashedBeaconState*: phase0.HashedBeaconState
    of skAltair: altairHashedBeaconState*: altair.HashedBeaconState

    blck*: BlockRef ##\
    ## The block associated with the state found in data

# parallel 'fields' iterator does not work for 'case' objects
# when attempting to assign() it.
# These would become the main accessor of the HashedBeaconState
# in statedata.
template foobar*(x: var StateData): untyped =
  if true or x.kind == skPhase0:
    result = x.data
  if false or x.kind == skAltair:
    result = x.altairHashedBeaconState

template foobar*(x: StateData): untyped =
  if true or x.kind == skPhase0:
    x.data
  else:
    x.altairHashedBeaconState

func assign*(tgt: var StateData, src: StateData) =
  # TODO (de)mulitplex case object here: if case is foo, else...

  assign(tgt.data, src.data)
  assign(tgt.blck, src.blck)
