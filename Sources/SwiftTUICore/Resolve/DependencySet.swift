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

/// A property-grained observable dependency key: an `@Observable` object paired
/// with the key path that was read on it.
///
/// Recorded *additively* alongside the coarse object token in
/// ``DependencySet/observableReads`` — never replacing it — so a key path miss
/// always falls back to object-token behavior (over-invalidate = safe). Only the
/// seams that hold a key path at read time can populate it (today: the
/// `@Bindable` subscript); plain `body` reads and `@Environment`-injected
/// observable reads have no key path and remain object-token only.
package struct ObservableKeyPathKey: Hashable {
  package var object: ObjectIdentifier
  package var keyPath: AnyKeyPath

  package init(object: ObjectIdentifier, keyPath: AnyKeyPath) {
    self.object = object
    self.keyPath = keyPath
  }
}

package struct DependencySet: Equatable {
  package var stateSlotReads: Set<StateSlotKey>
  package var environmentReads: Set<ObjectIdentifier>
  package var observableReads: Set<ObjectIdentifier>
  /// Property-grained observable reads, recorded additively alongside the object
  /// tokens in ``observableReads``. Used by the key-path invalidation narrowing
  /// (``ObservableKeyPathInvalidationConfiguration``); empty unless a key-path
  /// holding seam (`@Bindable`) recorded a read.
  package var observableKeyPathReads: Set<ObservableKeyPathKey>

  package init(
    stateSlotReads: Set<StateSlotKey> = [],
    environmentReads: Set<ObjectIdentifier> = [],
    observableReads: Set<ObjectIdentifier> = [],
    observableKeyPathReads: Set<ObservableKeyPathKey> = []
  ) {
    self.stateSlotReads = stateSlotReads
    self.environmentReads = environmentReads
    self.observableReads = observableReads
    self.observableKeyPathReads = observableKeyPathReads
  }
}
