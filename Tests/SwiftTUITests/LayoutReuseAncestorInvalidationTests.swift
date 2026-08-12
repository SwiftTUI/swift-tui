import Foundation
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite
struct LayoutReuseAncestorInvalidationTests {
  @Test("root invalidation still reuses clean descendant layout work")
  func rootInvalidationReusesCleanDescendantLayoutWork() {
    let renderer = DefaultRenderer(
      layoutEngine: .init(cache: MeasurementCache())
    )

    func makeRoot() -> some View {
      VStack(alignment: .leading, spacing: 1) {
        Text("Stable header")
        Text("Stable footer")
      }
    }

    _ = renderer.render(
      makeRoot(),
      context: .init(identity: testIdentity("LayoutReuse", "Root"))
    )

    let updated = renderer.render(
      makeRoot(),
      context: .init(
        identity: testIdentity("LayoutReuse", "Root"),
        invalidatedIdentities: [testIdentity("LayoutReuse", "Root")]
      )
    )

    // The two unchanged `Text` leaves are `Equatable` memo candidates and are
    // reused at resolve; the non-`Equatable` `VStack` recomputes.
    #expect(updated.diagnostics.work.resolvedNodesReused == 2)
    #expect(updated.diagnostics.work.measuredNodesComputed == 0)
    #expect(updated.diagnostics.work.measuredNodesReused == 3)
    #expect(updated.diagnostics.work.placedNodesComputed == 1)
    #expect(updated.diagnostics.work.placedNodesReused == 2)
  }

  @Test("nested invalidation still reuses clean sibling subtrees")
  func nestedInvalidationReusesCleanSiblingSubtrees() {
    let renderer = DefaultRenderer(
      layoutEngine: .init(cache: MeasurementCache())
    )
    final class BranchDetailBox: Sendable {
      private let detailStorage = LockedBox("Branch A detail")

      var detail: String {
        get { detailStorage.value }
        set { detailStorage.value = newValue }
      }
    }
    let box = BranchDetailBox()

    func makeRoot() -> some View {
      VStack(alignment: .leading, spacing: 1) {
        VStack(alignment: .leading, spacing: 0) {
          Text("Branch A header")
          Text(box.detail)
        }
        VStack(alignment: .leading, spacing: 0) {
          Text("Branch B header")
          Text("Branch B detail")
        }
      }
    }

    _ = renderer.render(
      makeRoot(),
      context: .init(identity: testIdentity("LayoutReuse", "NestedRoot"))
    )

    box.detail = "Branch A detail updated"

    let updated = renderer.render(
      makeRoot(),
      context: .init(
        identity: testIdentity("LayoutReuse", "NestedRoot"),
        invalidatedIdentities: [testIdentity("LayoutReuse", "NestedRoot", "VStack[0]", "VStack[1]")]
      )
    )

    // With the size-stability cutoff on by default (plan 2026-08-11-002
    // Stage 4), the invalidated-but-unchanged branch certifies in the
    // pre-pass and serves retained measurements instead of recomputing
    // (computed 3 -> 2, reused 4 -> 5). Placement is deliberately not
    // certified (D5), so the placed economy is unchanged.
    #expect(updated.diagnostics.work.measuredNodesComputed == 2)
    #expect(updated.diagnostics.work.measuredNodesReused == 5)
    #expect(updated.diagnostics.work.placedNodesComputed == 3)
    #expect(updated.diagnostics.work.placedNodesReused == 4)
  }
}
