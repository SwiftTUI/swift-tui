package struct StateSlotKey: Hashable, Sendable {
  package var owner: ViewNodeID
  package var slot: StateSlotIdentifier

  package init(owner: ViewNodeID, slot: StateSlotIdentifier) {
    self.owner = owner
    self.slot = slot
  }

  package init(owner: ViewNodeID, ordinal: Int) {
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
  package let rawValue: UInt

  package init(_ viewGraph: ViewGraph) {
    rawValue = UInt(bitPattern: ObjectIdentifier(viewGraph))
  }

  package init(rawValue: UInt) {
    self.rawValue = rawValue
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
}
