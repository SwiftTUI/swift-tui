package struct StateSlotKey: Hashable, Sendable {
  /// The immutable lifetime of the node that owns the slot.
  ///
  /// `ViewNodeID` is intentionally not part of this address: graph checkpoint
  /// rollback rewinds the raw-node allocator, so a later unrelated node can
  /// reuse the same raw ID. Owner-lifetime IDs are issued by the graph's
  /// non-checkpointed monotonic sequencer and therefore stay ABA-safe.
  package var owner: NodeOwnerLifetimeID
  package var slot: StateSlotIdentifier

  package init(owner: NodeOwnerLifetimeID, slot: StateSlotIdentifier) {
    self.owner = owner
    self.slot = slot
  }

  package init(owner: NodeOwnerLifetimeID, ordinal: Int) {
    self.init(owner: owner, slot: StateSlotIdentifier(ordinal: ordinal))
  }

  /// The slot's source-location ordinal. Diagnostics only — storage
  /// addressing must go through ``slot`` so path-qualified identities stay
  /// distinct.
  package var ordinal: Int {
    slot.ordinal
  }
}

package struct StateGraphScopeID: Hashable, Sendable {
  package let rawValue: UInt64

  @MainActor private static var nextRawValue: UInt64 = 0

  @MainActor
  package init(_ viewGraph: ViewGraph) {
    self = viewGraph.stateGraphScopeID
  }

  package init(rawValue: UInt64) {
    self.rawValue = rawValue
  }

  @MainActor
  package static func issue() -> Self {
    precondition(nextRawValue < .max, "StateGraphScopeID exhausted")
    nextRawValue += 1
    return Self(rawValue: nextRawValue)
  }
}

/// Graph-local, immutable lifetime identity for one authored state owner.
///
/// The value is meaningful only together with its graph scope. Unlike
/// `ViewNodeID`, its allocator is never checkpointed or rewound.
package struct NodeOwnerLifetimeID: Hashable, Comparable, Sendable, CustomStringConvertible {
  package let rawValue: UInt64

  package init(rawValue: UInt64) {
    self.rawValue = rawValue
  }

  package static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.rawValue < rhs.rawValue
  }

  package var description: String {
    "owner-lifetime-\(rawValue)"
  }
}

/// Sendable route from an authored callback to its exact graph-backed owner.
package struct StateOwnerHandle: Hashable, Sendable {
  package let graphScope: StateGraphScopeID
  package let ownerLifetime: NodeOwnerLifetimeID

  package init(
    graphScope: StateGraphScopeID,
    ownerLifetime: NodeOwnerLifetimeID
  ) {
    self.graphScope = graphScope
    self.ownerLifetime = ownerLifetime
  }
}

package struct DependencySet: Equatable {
  package var stateSlotReads: Set<StateSlotKey>
  package var environmentReads: Set<ObjectIdentifier>
  package var observableReads: Set<ObjectIdentifier>
  /// The exact identities a target-scoped runtime-focus side-field read
  /// compared against (all at or below the reader, per the framework read
  /// audit). Recorded alongside a target-scoped sentinel in
  /// `environmentReads`; the focus-move path predicate treats the reader as
  /// affected only when the moved identity is among these targets. Empty for
  /// broad-sentinel readers.
  package var focusComparisonTargets: Set<Identity>
  /// Reader-attributed-only environment keys this node WROTE during its last
  /// resolve (an authored `.environment`/`.transformEnvironment` below which
  /// the key's value is writer-controlled, not inherited). Consumed by the
  /// reader-scoped environment reuse toleration: a tolerated diff must deny
  /// when a changed key has a writer inside the candidate subtree — an
  /// interior write makes the subtree's stored values independent of the
  /// boundary's change, including the undetectable case where the written
  /// constant equals the boundary's prior value. Framework keys are never
  /// recorded (they never enter the toleration).
  package var environmentWrites: Set<ObjectIdentifier>

  package init(
    stateSlotReads: Set<StateSlotKey> = [],
    environmentReads: Set<ObjectIdentifier> = [],
    observableReads: Set<ObjectIdentifier> = [],
    focusComparisonTargets: Set<Identity> = [],
    environmentWrites: Set<ObjectIdentifier> = []
  ) {
    self.stateSlotReads = stateSlotReads
    self.environmentReads = environmentReads
    self.observableReads = observableReads
    self.focusComparisonTargets = focusComparisonTargets
    self.environmentWrites = environmentWrites
  }

  package mutating func formUnion(_ other: Self) {
    stateSlotReads.formUnion(other.stateSlotReads)
    environmentReads.formUnion(other.environmentReads)
    observableReads.formUnion(other.observableReads)
    focusComparisonTargets.formUnion(other.focusComparisonTargets)
    environmentWrites.formUnion(other.environmentWrites)
  }
}
