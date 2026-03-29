import Foundation
import Testing

@testable import Core
@testable import TerminalUI
@testable import View

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

    #expect(updated.diagnostics.resolvedNodesReused == 0)
    #expect(updated.diagnostics.measuredNodesComputed == 0)
    #expect(updated.diagnostics.measuredNodesReused == 3)
    #expect(updated.diagnostics.placedNodesComputed == 1)
    #expect(updated.diagnostics.placedNodesReused == 2)
  }
}
