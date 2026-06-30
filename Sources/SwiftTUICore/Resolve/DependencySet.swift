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

  package init(
    stateSlotReads: Set<StateSlotKey> = [],
    environmentReads: Set<ObjectIdentifier> = [],
    observableReads: Set<ObjectIdentifier> = []
  ) {
    self.stateSlotReads = stateSlotReads
    self.environmentReads = environmentReads
    self.observableReads = observableReads
  }
}
