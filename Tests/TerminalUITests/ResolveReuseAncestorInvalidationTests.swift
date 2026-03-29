import Foundation
import Testing

@testable import Core
@testable import TerminalUI
@testable import View

@Suite
struct ResolveReuseAncestorInvalidationTests {
  @Test("ancestor invalidation recomputes binding-driven descendants")
  func ancestorInvalidationRecomputesBindingDrivenDescendants() {
    let renderer = DefaultRenderer(
      layoutEngine: .init(cache: MeasurementCache())
    )
    let rootIdentity = testIdentity("Root")
    final class SelectionBox: @unchecked Sendable {
      var value = "Overview"
    }
    let box = SelectionBox()

    let selection = Binding<String>(
      get: { box.value },
      set: { box.value = $0 }
    )

    struct BindingDrivenRoot: View {
      let selection: Binding<String>

      var body: some View {
        VStack(alignment: .leading, spacing: 0) {
          Text("Header")
          Text(selection.wrappedValue)
        }
      }
    }

    _ = renderer.render(
      BindingDrivenRoot(selection: selection),
      context: .init(identity: rootIdentity)
    )
    box.value = "Styling"

    let updated = renderer.render(
      BindingDrivenRoot(selection: selection),
      context: .init(
        identity: rootIdentity,
        invalidatedIdentities: [rootIdentity]
      )
    )

    let rendered = updated.rasterSurface.lines.joined(separator: "\n")
    #expect(updated.diagnostics.resolvedNodesReused == 0)
    #expect(rendered.contains("Styling"))
    #expect(!rendered.contains("Overview"))
  }

  @Test("ancestor invalidation blocks clean descendant reuse")
  func ancestorInvalidationBlocksCleanDescendantReuse() {
    let renderer = DefaultRenderer(
      layoutEngine: .init(cache: MeasurementCache())
    )
    let rootIdentity = testIdentity("Root")

    struct StableRoot: View {
      var body: some View {
        VStack(alignment: .leading, spacing: 0) {
          Text("Stable")
          Text("AlsoStable")
        }
      }
    }

    _ = renderer.render(
      StableRoot(),
      context: .init(identity: rootIdentity)
    )

    let updated = renderer.render(
      StableRoot(),
      context: .init(
        identity: rootIdentity,
        invalidatedIdentities: [rootIdentity]
      )
    )

    #expect(updated.diagnostics.resolvedNodesReused == 0)
    #expect(updated.diagnostics.resolvedNodesComputed > 0)
  }
}
