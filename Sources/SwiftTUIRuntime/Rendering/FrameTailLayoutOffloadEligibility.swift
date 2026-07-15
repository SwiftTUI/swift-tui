import SwiftTUICore

// Layout-offload eligibility for the frame-tail renderer.
//
// The frame tail can run its layout pass on a background worker, but only when
// the resolved tree contains nothing that must run on the main actor. This
// file owns that classification: the public eligibility queries the run loop
// consults before scheduling.
//
// Three independent disqualifiers are checked:
//
//  - custom layouts whose handle reports `canRunOnWorker == false`,
//  - indexed child sources that cannot run on a worker,
//  - layout-realized content, which needs a prepared graph mid-layout.
//
// All three are answered in O(1) from the resolve-time
// `customLayoutFallbackSummary` aggregate that `ResolvedNode` maintains
// bottom-up (F35). The queries used to run recursive full-tree scans — up to
// three per call across seven call sites per frame — for a frame-constant
// answer. The recursive scans survive below only as the DEBUG drift oracle
// that pins the aggregate to the tree it summarizes.
extension FrameTailRenderer {
  func canOffloadLayout(
    _ input: FrameTailInput
  ) -> Bool {
    let summary = input.resolved.customLayoutFallbackSummary
    assertOffloadSummaryMatchesScans(input.resolved)
    return summary.count == 0
      && summary.mainActorOnlyIndexedChildSourceCount == 0
      && summary.layoutRealizedContentCount == 0
  }

  func needsIndexedChildSourceWorkerSnapshot(
    _ input: FrameTailInput
  ) -> Bool {
    let summary = input.resolved.customLayoutFallbackSummary
    assertOffloadSummaryMatchesScans(input.resolved)
    return summary.count == 0
      && summary.mainActorOnlyIndexedChildSourceCount > 0
      && summary.layoutRealizedContentCount == 0
      // Snapshotting pre-realizes EVERY source element on the main actor
      // before the tail can offload. Past this budget that pre-realization
      // costs more than offloading the tail wins: a windowed main-actor
      // tail realizes on the order of one viewport of rows per source
      // (proposal 2026-07-13-002 Stage 2.2b — the F144 async twin). The
      // frame then keeps the live sources and runs the tail on the main
      // actor (`canOffloadLayout` is already false for these trees).
      && summary.mainActorOnlyIndexedChildSourceElementCount
        <= Self.workerSnapshotElementBudget(for: input.proposal)
  }

  /// Four times the root proposal's larger dimension: generous against a
  /// windowed tail's per-source realization (viewport rows + overscan, a few
  /// measure entries per frame), so small sources — where the snapshot is
  /// cheap and offload genuinely wins — keep offloading unchanged.
  static func workerSnapshotElementBudget(for proposal: ProposedSize) -> Int {
    let width: Int =
      if case .finite(let value) = proposal.width { value } else { 0 }
    let height: Int =
      if case .finite(let value) = proposal.height { value } else { 0 }
    let bound = max(width, height)
    return bound > 0 ? 4 * bound : 256
  }

  func needsPreparedGraphDuringLayout(
    _ input: FrameTailInput
  ) -> Bool {
    assertOffloadSummaryMatchesScans(input.resolved)
    return input.resolved.customLayoutFallbackSummary.layoutRealizedContentCount > 0
  }

  /// DEBUG drift oracle: the O(1) summary answers must agree with the
  /// recursive scans they replaced. The summary is derived state maintained by
  /// `ResolvedNode`'s setters; a mutation path that bypasses them with a
  /// structural change (direct `_stored*` writes are documented same-shape
  /// only) would silently flip offload eligibility, so any disagreement here
  /// is a summary-maintenance bug, not an eligibility policy change.
  private func assertOffloadSummaryMatchesScans(_ resolved: ResolvedNode) {
    #if DEBUG
      let summary = resolved.customLayoutFallbackSummary
      assert(
        (summary.count > 0) == containsMainActorOnlyCustomLayout(resolved),
        "customLayoutFallbackSummary.count drifted from the resolved tree"
      )
      assert(
        (summary.mainActorOnlyIndexedChildSourceCount > 0)
          == containsMainActorOnlyIndexedChildSource(resolved),
        "customLayoutFallbackSummary.mainActorOnlyIndexedChildSourceCount drifted"
      )
      assert(
        summary.mainActorOnlyIndexedChildSourceElementCount
          == mainActorOnlyIndexedChildSourceElementScan(resolved),
        "customLayoutFallbackSummary.mainActorOnlyIndexedChildSourceElementCount drifted"
      )
      assert(
        (summary.layoutRealizedContentCount > 0) == containsLayoutRealizedContent(resolved),
        "customLayoutFallbackSummary.layoutRealizedContentCount drifted"
      )
    #endif
  }

  func containsMainActorOnlyCustomLayout(
    _ node: ResolvedNode
  ) -> Bool {
    if case .custom(let handle) = node.layoutBehavior,
      !handle.canRunOnWorker
    {
      return true
    }
    if let workerChildren = node.indexedChildSource?.workerResolvedChildren,
      workerChildren.contains(where: containsMainActorOnlyCustomLayout)
    {
      return true
    }
    return node.children.contains { containsMainActorOnlyCustomLayout($0) }
  }

  func containsMainActorOnlyIndexedChildSource(
    _ node: ResolvedNode
  ) -> Bool {
    if let source = node.indexedChildSource {
      if !source.canRunOnWorker {
        return true
      }
      if let workerChildren = source.workerResolvedChildren,
        workerChildren.contains(where: containsMainActorOnlyIndexedChildSource)
      {
        return true
      }
    }
    return node.children.contains { containsMainActorOnlyIndexedChildSource($0) }
  }

  func mainActorOnlyIndexedChildSourceElementScan(
    _ node: ResolvedNode
  ) -> Int {
    var total = 0
    if let source = node.indexedChildSource {
      if !source.canRunOnWorker {
        total += source.count
      }
      if let workerChildren = source.workerResolvedChildren {
        total += workerChildren.reduce(0) {
          $0 + mainActorOnlyIndexedChildSourceElementScan($1)
        }
      }
    }
    return node.children.reduce(total) {
      $0 + mainActorOnlyIndexedChildSourceElementScan($1)
    }
  }

  func containsLayoutRealizedContent(
    _ node: ResolvedNode
  ) -> Bool {
    if node.layoutRealizedContent != nil {
      return true
    }
    if let workerChildren = node.indexedChildSource?.workerResolvedChildren,
      workerChildren.contains(where: containsLayoutRealizedContent)
    {
      return true
    }
    return node.children.contains { containsLayoutRealizedContent($0) }
  }
}
