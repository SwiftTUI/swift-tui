import Foundation
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite
struct ResolveReuseAncestorInvalidationTests {
  @Test("ancestor invalidation recomputes binding-driven descendants")
  func ancestorInvalidationRecomputesBindingDrivenDescendants() {
    let renderer = DefaultRenderer(
      layoutEngine: .init(cache: MeasurementCache())
    )
    let rootIdentity = testIdentity("Root")
    final class SelectionBox: Sendable {
      private let valueStorage = LockedBox("Overview")

      var value: String {
        get { valueStorage.value }
        set { valueStorage.value = newValue }
      }
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
    #expect(updated.diagnostics.work.resolvedNodesReused == 0)
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

    #expect(updated.diagnostics.work.resolvedNodesReused == 0)
    #expect(updated.diagnostics.work.resolvedNodesComputed > 0)
  }

  @Test("ancestor invalidation recomputes List row labels derived from root state")
  func ancestorInvalidationRecomputesListRowLabels() {
    let renderer = DefaultRenderer(
      layoutEngine: .init(cache: MeasurementCache())
    )
    let rootIdentity = testIdentity("Root")

    final class SelectionBox: Sendable {
      private let selectedIndexStorage = LockedBox(0)

      var selectedIndex: Int {
        get { selectedIndexStorage.value }
        set { selectedIndexStorage.value = newValue }
      }
    }
    let selectionBox = SelectionBox()

    struct RootList: View {
      let value: Int
      let selection: Binding<Int>

      var body: some View {
        List(selection: selection) {
          ForEach([0, 2, 4], id: \.self) { preset in
            Text(preset == value ? "\(preset) *" : "\(preset)")
              .tag(preset)
          }
        }
        .frame(width: 16, height: 6, alignment: .topLeading)
      }
    }

    let selection = Binding<Int>(
      get: { selectionBox.selectedIndex },
      set: { selectionBox.selectedIndex = $0 }
    )

    _ = renderer.render(
      RootList(value: 0, selection: selection),
      context: .init(identity: rootIdentity)
    )
    selectionBox.selectedIndex = 2

    let updated = renderer.render(
      RootList(value: 2, selection: selection),
      context: .init(
        identity: rootIdentity,
        invalidatedIdentities: [rootIdentity]
      )
    )

    let rendered = updated.rasterSurface.lines.joined(separator: "\n")
    #expect(rendered.contains("2 *"))
    #expect(!rendered.contains("0 *"))
  }
}
