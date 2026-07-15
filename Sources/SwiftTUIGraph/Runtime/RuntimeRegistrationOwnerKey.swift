package struct RuntimeRegistrationOwnerKey: Hashable, Comparable, Sendable {
  package var viewNodeID: ViewNodeID?
  package var identity: Identity

  package init(
    viewNodeID: ViewNodeID? = nil,
    identity: Identity
  ) {
    self.viewNodeID = viewNodeID
    self.identity = identity
  }

  @MainActor
  package static func current(identity: Identity) -> Self {
    guard let node = ViewNodeContext.current else {
      return Self(identity: identity)
    }

    return Self(
      viewNodeID: node.viewNodeID,
      identity: identity
    )
  }

  package func matchesAnySubtreeRoot(
    _ roots: [Identity]
  ) -> Bool {
    roots.contains(where: matchesSubtreeRoot)
  }

  private func matchesSubtreeRoot(
    _ root: Identity
  ) -> Bool {
    identity == root || identity.isDescendant(of: root)
  }

  package static func < (
    lhs: RuntimeRegistrationOwnerKey,
    rhs: RuntimeRegistrationOwnerKey
  ) -> Bool {
    if lhs.identity != rhs.identity {
      return lhs.identity < rhs.identity
    }
    switch (lhs.viewNodeID, rhs.viewNodeID) {
    case (.some(let lhsID), .some(let rhsID)):
      if lhsID != rhsID {
        return lhsID < rhsID
      }
    case (.none, .some):
      return true
    case (.some, .none):
      return false
    case (.none, .none):
      break
    }
    return false
  }
}

/// Registration families whose subtree cleanup persists an explicit owner key.
/// The closed mapping from ``RuntimeRegistrationKind`` prevents a new owner-
/// keyed family from silently missing the F129 ownership contract.
package enum RuntimeRegistrationOwnerFamily: CaseIterable, Hashable, Sendable {
  case action
  case keyHandler
  case termination
  case pointer
  case gesture
  case gestureState
  case task
  case command
  case dropDestination
}

extension RuntimeRegistrationKind {
  package var ownerFamily: RuntimeRegistrationOwnerFamily? {
    switch self {
    case .action: .action
    case .keyHandler: .keyHandler
    case .termination: .termination
    case .pointerHandler: .pointer
    case .gesture: .gesture
    case .gestureState: .gestureState
    case .task: .task
    case .command: .command
    case .dropDestination: .dropDestination
    case .defaultFocus, .focusBinding, .focusedValues, .scrollPosition, .lifecycle,
      .preferenceObservation:
      nil
    }
  }
}
