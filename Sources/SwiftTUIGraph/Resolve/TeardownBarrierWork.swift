/// A reason a runtime node is owed a decision at the teardown barrier.
///
/// Work is deliberately separate from `LifetimeAnchor`: debt cannot grant a
/// node the right to remain live.
package enum TeardownWorkReason: CaseIterable, Hashable, Sendable {
  case resolveScopeScratch
  case entityRoutedRemoval
  case absorbedShadow
  case departedNavigationSurface
  /// A visited node a departing-subtree descent spared (the re-adoption
  /// keep-guard). The spare is provisional: "visited this frame" also holds
  /// for a node a SUPERSEDED same-frame pass resolved and the committed pass
  /// dropped (the toolbar-strip item churn strand), which the descent cannot
  /// distinguish from a genuine re-adoption mid-frame. The barrier — where
  /// every apply has settled — keeps the node iff a durable anchor claims
  /// it, and reclaims the strand otherwise.
  case sparedVisitedDescent
}

package struct TeardownBarrierWork: Equatable, Sendable {
  package var reasonsByNodeID: [ViewNodeID: Set<TeardownWorkReason>]

  package init(
    reasonsByNodeID: [ViewNodeID: Set<TeardownWorkReason>] = [:]
  ) {
    self.reasonsByNodeID = reasonsByNodeID
  }

  package mutating func enqueue(
    _ reason: TeardownWorkReason,
    for nodeID: ViewNodeID
  ) {
    reasonsByNodeID[nodeID, default: []].insert(reason)
  }

  package mutating func remove(
    _ reason: TeardownWorkReason,
    for nodeID: ViewNodeID
  ) {
    reasonsByNodeID[nodeID]?.remove(reason)
    if reasonsByNodeID[nodeID]?.isEmpty == true {
      reasonsByNodeID.removeValue(forKey: nodeID)
    }
  }

  package mutating func removeNode(_ nodeID: ViewNodeID) {
    reasonsByNodeID.removeValue(forKey: nodeID)
  }

  package mutating func consumeReasons(
    for nodeID: ViewNodeID
  ) -> Set<TeardownWorkReason> {
    reasonsByNodeID.removeValue(forKey: nodeID) ?? []
  }

  package func reasons(
    for nodeID: ViewNodeID
  ) -> Set<TeardownWorkReason> {
    reasonsByNodeID[nodeID, default: []]
  }

  package func nodeIDs(
    for reason: TeardownWorkReason
  ) -> Set<ViewNodeID> {
    Set(
      reasonsByNodeID.compactMap { nodeID, reasons in
        reasons.contains(reason) ? nodeID : nil
      })
  }

  package var nodeIDs: Set<ViewNodeID> {
    Set(reasonsByNodeID.keys)
  }

  package var reasonCount: Int {
    reasonsByNodeID.values.reduce(into: 0) { count, reasons in
      count += reasons.count
    }
  }

  package var isEmpty: Bool {
    reasonsByNodeID.isEmpty
  }
}
