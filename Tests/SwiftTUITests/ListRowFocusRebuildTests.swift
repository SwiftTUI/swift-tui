import Observation
import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

// swift-tui issue #4: "List arrow keys move selection but not focus — Return
// always activates the first row".
//
// Mechanism: a selectable `List` stamps `hostedCollectionItem` onto ITS copy of
// every row child at resolve time, and the semantics pass derives each row's
// focus region from that stamp. The row's own committed value never carries
// it, so a `ViewNode.snapshot()` rebuild that re-pulls the children's committed
// values (any frame after a row re-applied or the list was marked dirty without
// re-resolving) served a list whose rows carried no stamp. That frame emitted
// zero row focus regions, the tracker cleared focus, and the convergence
// re-render then silently re-seated focus on `ListRow[0]` while the selection
// still sat on the row the user had arrowed to — Return activated row 0.
//
// Both journeys below were RED before the rebuild carried the parent-authored
// stamps forward (`ResolvedNode.carryingParentAuthoredSemantics(from:)`).

private struct RebuildRow: Identifiable, Hashable {
  let id: Int
  let title: String
}

private let rebuildRows = [
  RebuildRow(id: 0, title: "Row 1"),
  RebuildRow(id: 1, title: "Row 2"),
  RebuildRow(id: 2, title: "Row 3"),
]

/// The reporter's app, verbatim in shape, plus a `Selection:` readout.
private struct ReporterListView: View {
  @State private var selection: Int?
  @State private var activated = "(none)"

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("Activated: \(activated)")
      Text("Selection: \(selection.map(String.init) ?? "nil")")
      List(
        selection: $selection,
        onActivate: { id in
          activated = rebuildRows.first { $0.id == id }?.title ?? "?"
        }
      ) {
        ForEach(rebuildRows) { row in
          Text(row.title).tag(row.id)
        }
      }
    }
    .padding(1)
  }
}

@Observable
@MainActor
private final class ObservableRowModel {
  var labels = ["Row 1", "Row 2", "Row 3"]
}

/// A row whose content depends on an observable the list itself never reads,
/// so a label change re-resolves only that row — the list's committed
/// snapshot goes stale without the list re-resolving.
private struct ObservableRowLabel: View {
  let model: ObservableRowModel
  let index: Int

  var body: some View {
    Text(model.labels[index])
  }
}

private struct ObservableRowsListView: View {
  let model: ObservableRowModel
  @State private var selection: Int?
  @State private var activated = "(none)"

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("Activated: \(activated)")
      List(
        selection: $selection,
        onActivate: { id in
          activated = "Row \(id + 1)"
        }
      ) {
        ForEach(0..<3, id: \.self) { index in
          ObservableRowLabel(model: model, index: index).tag(index)
        }
      }
    }
    .padding(1)
  }
}

@MainActor
@Suite(.serialized)
struct ListRowFocusRebuildTests {
  private func rowFocusRegionIdentities<Content: View>(
    _ harness: StressRuntimeHarness<Content>
  ) -> [String] {
    harness.runLoop.latestSemanticSnapshot.focusRegions
      .map(\.identity.description)
      .filter { $0.contains("ListRow[") }
      .map { String($0.split(separator: "/").last ?? "") }
  }

  @Test(
    "a row-content change while a row is focused keeps every row focus region and the focused row")
  func rowContentChangeKeepsRowFocus() throws {
    let model = ObservableRowModel()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ListRowFocusRebuildContent"),
      size: .init(width: 40, height: 12)
    ) {
      ObservableRowsListView(model: model)
    }
    defer { harness.shutdown() }
    // Production enables selective evaluation after the first frame; the
    // rebuild path under test only exists once clean subtrees are reused.
    harness.runLoop.renderer.enableSelectiveEvaluation()

    _ = try harness.pressKey(KeyPress(.arrowDown))
    let focusedRow = try #require(harness.runLoop.focusTracker.currentFocusIdentity)
    #expect(focusedRow.description.hasSuffix("ListRow[1]"))
    #expect(harness.frame.contains("▌ Row 2"))

    // Only row 3's label re-resolves; the list node is never re-evaluated.
    model.labels[2] = "Row 3 (updated)"
    var rendered = 0
    try harness.runLoop.renderPendingFrames(renderedFrames: &rendered)

    #expect(
      rowFocusRegionIdentities(harness) == ["ListRow[0]", "ListRow[1]", "ListRow[2]"],
      "every row keeps its focus region across the rebuild:\n\(harness.frame)"
    )
    #expect(
      harness.runLoop.focusTracker.currentFocusIdentity == focusedRow,
      "focus stays on the row the user arrowed to:\n\(harness.frame)"
    )
    #expect(harness.frame.contains("▌ Row 2"))
    #expect(harness.frame.contains("Row 3 (updated)"))

    // Return activates the focused (and selected) row, not row 0.
    _ = try harness.pressKey(KeyPress(.return))
    #expect(harness.frame.contains("Activated: Row 2"), "\(harness.frame)")
  }

  @Test("arrow, an inert key, then Return activates the arrowed-to row under the async driver")
  func inertKeyAfterSelectionKeepsRowFocusUnderAsyncDriver() async throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ListRowFocusRebuildInertKey"),
      size: .init(width: 40, height: 12)
    ) {
      ReporterListView()
    }
    defer { harness.shutdown() }
    harness.runLoop.renderer.enableSelectiveEvaluation()

    // The production run loop drives the async renderer; its post-frame
    // state-slot reconciliation marks the list dirty without re-resolving it,
    // which is what leaves the list's committed snapshot stale for the next
    // no-invalidation input frame (the operator's `Escape` in the report).
    func press(_ key: KeyEvent) async throws {
      #expect(harness.runLoop.handle(.input(.key(KeyPress(key)))) == nil)
      var rendered = 0
      try await harness.runLoop.renderPendingFramesAsync(renderedFrames: &rendered)
    }

    try await press(.arrowDown)
    let focusedRow = try #require(harness.runLoop.focusTracker.currentFocusIdentity)
    #expect(focusedRow.description.hasSuffix("ListRow[1]"))
    #expect(harness.frame.contains("Selection: 1"))
    #expect(harness.frame.contains("▌ Row 2"))

    // Escape is inert for a List (no portal, no navigation stack): it must
    // leave both the row focus regions and the focused row exactly as they
    // were. This was the operator-reproduced journey in issue #4.
    try await press(.escape)
    #expect(
      rowFocusRegionIdentities(harness) == ["ListRow[0]", "ListRow[1]", "ListRow[2]"],
      "an inert key must not drop the row focus regions:\n\(harness.frame)"
    )
    #expect(
      harness.runLoop.focusTracker.currentFocusIdentity == focusedRow,
      "an inert key must not move row focus:\n\(harness.frame)"
    )
    #expect(harness.frame.contains("▌ Row 2"), "\(harness.frame)")

    try await press(.return)
    #expect(harness.frame.contains("Activated: Row 2"), "\(harness.frame)")
    #expect(harness.frame.contains("Selection: 1"), "\(harness.frame)")
  }
}
