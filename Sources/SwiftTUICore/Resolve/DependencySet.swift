package struct StateSlotKey: Hashable, Sendable {
  package var owner: ViewNodeID
  package var ordinal: Int

  package init(owner: ViewNodeID, ordinal: Int) {
    self.owner = owner
    self.ordinal = ordinal
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

  package init(
    stateSlotReads: Set<StateSlotKey> = [],
    environmentReads: Set<ObjectIdentifier> = [],
    observableReads: Set<ObjectIdentifier> = [],
    focusComparisonTargets: Set<Identity> = []
  ) {
    self.stateSlotReads = stateSlotReads
    self.environmentReads = environmentReads
    self.observableReads = observableReads
    self.focusComparisonTargets = focusComparisonTargets
  }
}
