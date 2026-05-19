import SwiftTUICore

/// Bounds how many extra render passes the run loop may spend converging
/// focus and scroll state within a single frame.
///
/// Focus/scroll synchronization can require re-rendering: applying a desired
/// focus request changes the semantic graph, which may surface new sync
/// candidates. The budget is derived from the graph size so convergence stays
/// bounded — every rerender must be justified by a visible candidate, plus one
/// final pass to confirm the synchronized tree.
package struct FocusSyncRerenderBudget: Equatable, Sendable {
  package let maximumRerenders: Int
  package private(set) var rerenderCount: Int

  package init(maximumRerenders: Int) {
    precondition(maximumRerenders > 0)
    self.maximumRerenders = maximumRerenders
    rerenderCount = 0
  }

  /// Derives the convergence budget from the semantic graph that can
  /// participate in focus/scroll synchronization. Each rerender must be
  /// justified by a visible sync candidate, plus one final pass to confirm the
  /// synchronized tree.
  package static func derived(from semanticSnapshot: SemanticSnapshot) -> Self {
    let syncCandidateCount =
      semanticSnapshot.focusRegions.count
      + semanticSnapshot.scrollRoutes.count
      + semanticSnapshot.scrollTargets.count
      + semanticSnapshot.accessibilityNodes.count
    return Self(maximumRerenders: max(1, syncCandidateCount + 1))
  }

  package mutating func expandIfNeeded(for semanticSnapshot: SemanticSnapshot) {
    let derived = Self.derived(from: semanticSnapshot)
    guard derived.maximumRerenders > maximumRerenders else {
      return
    }
    self = Self(
      maximumRerenders: derived.maximumRerenders,
      rerenderCount: rerenderCount
    )
  }

  private init(
    maximumRerenders: Int,
    rerenderCount: Int
  ) {
    precondition(maximumRerenders > 0)
    self.maximumRerenders = maximumRerenders
    self.rerenderCount = rerenderCount
  }

  /// Returns `true` when another focus-sync rerender is still allowed.
  package mutating func recordRerender() -> Bool {
    rerenderCount += 1
    return rerenderCount < maximumRerenders
  }
}
