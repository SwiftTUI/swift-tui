package struct StateSlotKey: Hashable, Sendable {
  package var identity: Identity
  package var ordinal: Int

  package init(identity: Identity, ordinal: Int) {
    self.identity = identity
    self.ordinal = ordinal
  }
}

package struct DependencySet: Equatable, Sendable {
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
