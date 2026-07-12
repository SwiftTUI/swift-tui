import Foundation
import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("SwiftTUI table and outline stress behavior", .serialized)
struct FrameworkStressTableOutlineTests {}

private func tableOutlineText(_ snapshot: RenderSnapshot) -> String {
  snapshot.rasterSurface.lines.joined(separator: "\n")
}

private func tableOutlineContainsInOrder(_ tokens: [String], in text: String) -> Bool {
  var cursor = text.startIndex
  for token in tokens {
    guard let range = text.range(of: token, range: cursor..<text.endIndex) else {
      return false
    }
    cursor = range.upperBound
  }
  return true
}

// MARK: - Attempt 001: table column contract replacement

extension FrameworkStressTableOutlineTests {
  @Test("stress table outline 001 table columns replace every retained contract field")
  func tableOutline001TableColumnsReplaceEveryRetainedContractField() {
    // Hypothesis: Table's value-collapsed draw payload can retain an earlier
    // column title, width, order, or alignment after the live array changes.
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("TableOutline001")

    for generation in 0..<20 {
      let root = TableOutline001Root(generation: generation)
      let retained = renderer.render(
        root,
        context: .init(
          identity: identity,
          invalidatedIdentities: generation == 0 ? [] : [identity]
        ),
        proposal: .init(width: 28, height: 7)
      )
      let fresh = DefaultRenderer().render(
        root,
        context: .init(identity: identity),
        proposal: .init(width: 28, height: 7)
      )

      #expect(retained.rasterSurface == fresh.rasterSurface)
      #expect(retained.resolvedTree.drawPayload == fresh.resolvedTree.drawPayload)
      #expect(tableOutlineText(retained).contains("N\(generation)"))
      #expect(tableOutlineText(retained).contains("V\(generation)"))
    }
  }
}

@MainActor
private struct TableOutline001Root: View {
  let generation: Int

  private var columns: [TableColumn] {
    if generation.isMultiple(of: 2) {
      return [
        .init("N\(generation)", width: 8, alignment: .leading, titleAlignment: .center),
        .init("V\(generation)", width: 5, alignment: .trailing, titleAlignment: .leading),
      ]
    }
    return [
      .init("V\(generation)", width: 6, alignment: .center, titleAlignment: .trailing),
      .init("N\(generation)", width: 7, alignment: .trailing, titleAlignment: .center),
    ]
  }

  var body: some View {
    Table(selection: .constant(1), columns: columns) {
      TableRow {
        Text("name-\(generation)")
        Text("value-\(generation)")
      }
      .tag(1)
    }
    .frame(width: 28, height: 7, alignment: .topLeading)
  }
}

// MARK: - Attempt 002: table column cardinality churn

extension FrameworkStressTableOutlineTests {
  @Test("stress table outline 002 table column cardinality rebuilds cell mapping")
  func tableOutline002TableColumnCardinalityRebuildsCellMapping() {
    // Hypothesis: changing the number of columns can leave retained separators
    // or cell-to-column indices from the prior table payload.
    struct Root: View {
      let generation: Int

      var body: some View {
        Table(
          selection: .constant(1),
          columns: generation.isMultiple(of: 2)
            ? [.init("Only", width: 8)]
            : [
              .init("A", width: 6),
              .init("B", width: 7, alignment: .center),
              .init("C", width: 5, alignment: .trailing),
            ]
        ) {
          TableRow {
            Text("A-\(generation)")
            Text("B-\(generation)")
            Text("C-\(generation)")
          }
          .tag(1)
        }
        .frame(width: 34, height: 7, alignment: .topLeading)
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("TableOutline002")
    for generation in 0..<18 {
      let root = Root(generation: generation)
      let retained = renderer.render(
        root,
        context: .init(
          identity: identity,
          invalidatedIdentities: generation == 0 ? [] : [identity]
        ),
        proposal: .init(width: 34, height: 7)
      )
      let fresh = DefaultRenderer().render(
        root,
        context: .init(identity: identity),
        proposal: .init(width: 34, height: 7)
      )

      #expect(retained.rasterSurface == fresh.rasterSurface)
      #expect(retained.resolvedTree.drawPayload == fresh.resolvedTree.drawPayload)
      #expect(tableOutlineText(retained).contains("A-\(generation)"))
      #expect(
        tableOutlineText(retained).contains("C-\(generation)") == !generation.isMultiple(of: 2))
    }
  }
}

// MARK: - Attempt 003: table header visibility churn

extension FrameworkStressTableOutlineTests {
  @Test("stress table outline 003 table header visibility leaves no stale row")
  func tableOutline003TableHeaderVisibilityLeavesNoStaleRow() {
    // Hypothesis: toggling the environment-driven header row can preserve its
    // old height or paint after the header payload becomes hidden.
    struct Root: View {
      let generation: Int

      var body: some View {
        Table(
          selection: .constant(1),
          columns: [.init("Header-\(generation)", width: 14)]
        ) {
          TableRow { Text("row-\(generation)") }.tag(1)
        }
        .tableHeaders(generation.isMultiple(of: 2) ? .visible : .hidden)
        .frame(width: 20, height: 7, alignment: .topLeading)
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("TableOutline003")
    for generation in 0..<20 {
      let root = Root(generation: generation)
      let retained = renderer.render(
        root,
        context: .init(
          identity: identity,
          invalidatedIdentities: generation == 0 ? [] : [identity]
        ),
        proposal: .init(width: 20, height: 7)
      )
      let fresh = DefaultRenderer().render(
        root,
        context: .init(identity: identity),
        proposal: .init(width: 20, height: 7)
      )
      let rendered = tableOutlineText(retained)

      #expect(retained.rasterSurface == fresh.rasterSurface)
      #expect(retained.measuredTree.measuredSize == fresh.measuredTree.measuredSize)
      #expect(rendered.contains("Header-\(generation)") == generation.isMultiple(of: 2))
      #expect(rendered.contains("row-\(generation)"))
    }
  }
}

// MARK: - Attempt 004: table row reorder with live payloads

extension FrameworkStressTableOutlineTests {
  @Test("stress table outline 004 table row reorder keeps current cells and selection index")
  func tableOutline004TableRowReorderKeepsCurrentCellsAndSelectionIndex() {
    // Hypothesis: recursive table-row collapse can retain an old row index
    // after stable entities reorder while their cell payloads also change.
    struct Row: Identifiable {
      let id: Int
      let label: String
    }
    struct Root: View {
      let rows: [Row]

      var body: some View {
        Table(selection: .constant(2), columns: [.init("Rows", width: 14)]) {
          ForEach(rows) { row in
            TableRow { Text(row.label) }.tag(row.id)
          }
        }
        .frame(width: 20, height: 10, alignment: .topLeading)
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("TableOutline004")
    for generation in 0..<20 {
      let rows = [
        Row(id: 1, label: "A-\(generation)"),
        Row(id: 2, label: "B-\(generation)"),
        Row(id: 3, label: "C-\(generation)"),
      ]
      let ordered = generation.isMultiple(of: 2) ? rows : [rows[2], rows[0], rows[1]]
      let root = Root(rows: ordered)
      let retained = renderer.render(
        root,
        context: .init(
          identity: identity,
          invalidatedIdentities: generation == 0 ? [] : [identity]
        ),
        proposal: .init(width: 20, height: 10)
      )
      let fresh = DefaultRenderer().render(
        root,
        context: .init(identity: identity),
        proposal: .init(width: 20, height: 10)
      )
      let rendered = tableOutlineText(retained)

      #expect(retained.rasterSurface == fresh.rasterSurface)
      #expect(retained.resolvedTree.drawPayload == fresh.resolvedTree.drawPayload)
      #expect(tableOutlineContainsInOrder(ordered.map(\.label), in: rendered))
    }
  }
}

// MARK: - Attempt 005: table empty-to-scrollable cardinality

extension FrameworkStressTableOutlineTests {
  @Test("stress table outline 005 table zero to many rows rebuilds scroll extent")
  func tableOutline005TableZeroToManyRowsRebuildsScrollExtent() {
    // Hypothesis: a table crossing zero rows can retain stale selection,
    // viewport, or scroll-indicator fields in its collapsed payload.
    struct Root: View {
      let count: Int
      let generation: Int

      var body: some View {
        Table(selection: .constant(4), columns: [.init("Rows", width: 12)]) {
          ForEach(0..<count) { row in
            TableRow { Text("r\(row)-g\(generation)") }.tag(row)
          }
        }
        .frame(width: 18, height: 6, alignment: .topLeading)
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("TableOutline005")
    for generation in 0..<20 {
      let count = generation.isMultiple(of: 2) ? 0 : 12
      let root = Root(count: count, generation: generation)
      let retained = renderer.render(
        root,
        context: .init(
          identity: identity,
          invalidatedIdentities: generation == 0 ? [] : [identity]
        ),
        proposal: .init(width: 18, height: 6)
      )
      let fresh = DefaultRenderer().render(
        root,
        context: .init(identity: identity),
        proposal: .init(width: 18, height: 6)
      )
      let rendered = tableOutlineText(retained)

      #expect(retained.rasterSurface == fresh.rasterSurface)
      #expect(retained.semanticSnapshot == fresh.semanticSnapshot)
      #expect(rendered.contains("r4-g\(generation)") == (count > 0))
      #expect((rendered.contains("↑") || rendered.contains("↓")) == (count > 0))
    }
  }
}

// MARK: - Attempt 006: conditional table-cell topology

extension FrameworkStressTableOutlineTests {
  @Test("stress table outline 006 conditional table cells follow current row topology")
  func tableOutline006ConditionalTableCellsFollowCurrentRowTopology() {
    // Hypothesis: a TableRow that alternates between one and three declared
    // cells can retain the departed cells in its value-collapsed row payload.
    struct Root: View {
      let generation: Int

      var body: some View {
        Table(
          selection: .constant(1),
          columns: [
            .init("A", width: 7),
            .init("B", width: 7),
            .init("C", width: 7),
          ]
        ) {
          TableRow {
            Text("a-\(generation)")
            if !generation.isMultiple(of: 2) {
              Text("b-\(generation)")
              Text("c-\(generation)")
            }
          }
          .tag(1)
        }
        .frame(width: 30, height: 7, alignment: .topLeading)
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("TableOutline006")
    for generation in 0..<20 {
      let root = Root(generation: generation)
      let retained = renderer.render(
        root,
        context: .init(
          identity: identity,
          invalidatedIdentities: generation == 0 ? [] : [identity]
        ),
        proposal: .init(width: 30, height: 7)
      )
      let fresh = DefaultRenderer().render(
        root,
        context: .init(identity: identity),
        proposal: .init(width: 30, height: 7)
      )
      let rendered = tableOutlineText(retained)

      #expect(retained.rasterSurface == fresh.rasterSurface)
      #expect(retained.resolvedTree.drawPayload == fresh.resolvedTree.drawPayload)
      #expect(rendered.contains("a-\(generation)"))
      #expect(rendered.contains("c-\(generation)") == !generation.isMultiple(of: 2))
    }
  }
}

// MARK: - Attempt 007: table row-style replacement

extension FrameworkStressTableOutlineTests {
  @Test("stress table outline 007 table row styles replace retained paint metadata")
  func tableOutline007TableRowStylesReplaceRetainedPaintMetadata() {
    // Hypothesis: Table's detached row subtrees can preserve an earlier row
    // foreground, background, or separator policy after the live modifiers change.
    struct Root: View {
      let generation: Int

      var body: some View {
        Table(selection: .constant(1), columns: [.init("Styled", width: 12)]) {
          TableRow { Text("styled-\(generation)") }
            .tag(1)
            .listRowBackground(generation.isMultiple(of: 2) ? Color.red : .blue)
            .listRowForegroundStyle(generation.isMultiple(of: 2) ? Color.yellow : .cyan)
            .listRowSeparator(
              generation.isMultiple(of: 2) ? .hidden : .visible,
              edges: generation.isMultiple(of: 2) ? .bottom : .top
            )
        }
        .frame(width: 20, height: 7, alignment: .topLeading)
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("TableOutline007")
    for generation in 0..<20 {
      let root = Root(generation: generation)
      let retained = renderer.render(
        root,
        context: .init(
          identity: identity,
          invalidatedIdentities: generation == 0 ? [] : [identity]
        ),
        proposal: .init(width: 20, height: 7)
      )
      let fresh = DefaultRenderer().render(
        root,
        context: .init(identity: identity),
        proposal: .init(width: 20, height: 7)
      )

      #expect(retained.rasterSurface == fresh.rasterSurface)
      #expect(retained.resolvedTree.drawPayload == fresh.resolvedTree.drawPayload)
      #expect(tableOutlineText(retained).contains("styled-\(generation)"))
    }
  }
}

// MARK: - Attempt 008: duplicate table tags under reorder

extension FrameworkStressTableOutlineTests {
  @Test("stress table outline 008 duplicate table tags select the current first occurrence")
  func tableOutline008DuplicateTableTagsSelectCurrentFirstOccurrence() {
    // Hypothesis: selectedRowIndex can remain attached to the former first
    // matching tag when duplicate-tagged rows reorder or one occurrence departs.
    struct Row: Identifiable {
      let id: Int
      let tag: Int
      let label: String
    }
    struct Root: View {
      let rows: [Row]
      let tableIdentity: Identity

      var body: some View {
        Table(selection: .constant(7), columns: [.init("Rows", width: 12)]) {
          ForEach(rows) { row in
            TableRow { Text(row.label) }.tag(row.tag)
          }
        }
        .id(tableIdentity)
      }
    }

    let a = Row(id: 1, tag: 7, label: "duplicate-A")
    let b = Row(id: 2, tag: 7, label: "duplicate-B")
    let c = Row(id: 3, tag: 8, label: "other-C")
    let variants = [[a, b, c], [b, c, a], [c, a], [a, c, b]]
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("TableOutline008")
    let tableIdentity = testIdentity("TableOutline008", "Table")
    var environment = EnvironmentValues()
    environment.focusedIdentity = tableIdentity

    for generation in 0..<20 {
      let rows = variants[generation % variants.count]
      let root = Root(rows: rows, tableIdentity: tableIdentity)
      let retained = renderer.render(
        root,
        context: .init(
          identity: rootIdentity,
          environmentValues: environment,
          invalidatedIdentities: generation == 0 ? [] : [rootIdentity],
          applyEnvironmentValues: true
        ),
        proposal: .init(width: 20, height: 9)
      )
      let fresh = DefaultRenderer().render(
        root,
        context: .init(
          identity: rootIdentity,
          environmentValues: environment,
          applyEnvironmentValues: true
        ),
        proposal: .init(width: 20, height: 9)
      )
      guard case .table(let payload) = retained.resolvedTree.drawPayload else {
        Issue.record("expected retained table payload")
        return
      }

      #expect(retained.rasterSurface == fresh.rasterSurface)
      #expect(payload.selectedRowIndex == rows.firstIndex { $0.tag == 7 })
    }
  }
}

// MARK: - Attempt 009: table key-binding retarget

extension FrameworkStressTableOutlineTests {
  @Test("stress table outline 009 table key handler writes only the current binding")
  func tableOutline009TableKeyHandlerWritesOnlyCurrentBinding() {
    // Hypothesis: Table's detached row collapse can restore a key handler whose
    // closure still owns the selection binding from an earlier root value.
    final class SelectionBox {
      var value = 1
      var writes: [Int] = []
    }
    struct Root: View {
      let box: SelectionBox
      let tableIdentity: Identity

      var body: some View {
        Table(
          selection: Binding(
            get: { box.value },
            set: {
              box.value = $0
              box.writes.append($0)
            }
          ),
          columns: [.init("Rows", width: 10)]
        ) {
          TableRow { Text("first") }.tag(1)
          TableRow { Text("second") }.tag(2)
        }
        .id(tableIdentity)
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("TableOutline009")
    let tableIdentity = testIdentity("TableOutline009", "Table")
    var priorBoxes: [SelectionBox] = []

    for generation in 0..<16 {
      let box = SelectionBox()
      let registry = LocalKeyHandlerRegistry()
      _ = renderer.render(
        Root(box: box, tableIdentity: tableIdentity),
        context: .init(
          identity: rootIdentity,
          invalidatedIdentities: generation == 0 ? [] : [rootIdentity],
          localKeyHandlerRegistry: registry,
          applyEnvironmentValues: true
        ),
        proposal: .init(width: 18, height: 8)
      )

      #expect(registry.dispatch(identity: tableIdentity, event: .arrowDown))
      #expect(box.value == 2)
      #expect(box.writes == [2])
      #expect(priorBoxes.allSatisfy { $0.value == 2 && $0.writes == [2] })
      priorBoxes.append(box)
    }
  }
}

// MARK: - Attempt 010: table key-order replacement

extension FrameworkStressTableOutlineTests {
  @Test("stress table outline 010 table key navigation follows reordered tags")
  func tableOutline010TableKeyNavigationFollowsReorderedTags() {
    // Hypothesis: Table's key closure can refresh its binding but retain the
    // selectableTags array captured before stable rows reordered.
    final class SelectionBox { var value = 1 }
    struct Row: Identifiable { let id: Int }
    struct Root: View {
      let rows: [Row]
      let box: SelectionBox
      let tableIdentity: Identity

      var body: some View {
        Table(
          selection: Binding(get: { box.value }, set: { box.value = $0 }),
          columns: [.init("Rows", width: 8)]
        ) {
          ForEach(rows) { row in
            TableRow { Text("row-\(row.id)") }.tag(row.id)
          }
        }
        .id(tableIdentity)
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("TableOutline010")
    let tableIdentity = testIdentity("TableOutline010", "Table")
    let box = SelectionBox()
    let variants = [[1, 2, 3], [3, 1, 2], [2, 3, 1]]

    for generation in 0..<18 {
      let order = variants[generation % variants.count]
      box.value = order[0]
      let registry = LocalKeyHandlerRegistry()
      _ = renderer.render(
        Root(rows: order.map(Row.init(id:)), box: box, tableIdentity: tableIdentity),
        context: .init(
          identity: rootIdentity,
          invalidatedIdentities: generation == 0 ? [] : [rootIdentity],
          localKeyHandlerRegistry: registry,
          applyEnvironmentValues: true
        ),
        proposal: .init(width: 16, height: 9)
      )

      #expect(registry.dispatch(identity: tableIdentity, event: .arrowDown))
      #expect(box.value == order[1])
    }
  }
}

// MARK: - Attempt 011: table handler restoration after disablement

extension FrameworkStressTableOutlineTests {
  @Test("stress table outline 011 reenabled table installs its current binding")
  func tableOutline011ReenabledTableInstallsCurrentBinding() {
    // Hypothesis: removing handlers through a disabled ancestor can restore the
    // pre-disable Table selection closure when the control becomes enabled again.
    final class SelectionBox {
      var value = 1
      var writes = 0
    }
    struct Root: View {
      let box: SelectionBox
      let enabled: Bool
      let tableIdentity: Identity

      var body: some View {
        Table(
          selection: Binding(
            get: { box.value },
            set: {
              box.value = $0
              box.writes += 1
            }
          ),
          columns: [.init("Rows", width: 8)]
        ) {
          TableRow { Text("one") }.tag(1)
          TableRow { Text("two") }.tag(2)
        }
        .id(tableIdentity)
        .disabled(!enabled)
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("TableOutline011")
    let tableIdentity = testIdentity("TableOutline011", "Table")
    var retired: [SelectionBox] = []

    for generation in 0..<18 {
      let enabled = generation % 3 == 2
      let box = SelectionBox()
      let registry = LocalKeyHandlerRegistry()
      _ = renderer.render(
        Root(box: box, enabled: enabled, tableIdentity: tableIdentity),
        context: .init(
          identity: rootIdentity,
          invalidatedIdentities: generation == 0 ? [] : [rootIdentity],
          localKeyHandlerRegistry: registry,
          applyEnvironmentValues: true
        ),
        proposal: .init(width: 16, height: 8)
      )

      #expect(registry.dispatch(identity: tableIdentity, event: .arrowDown) == enabled)
      #expect(box.value == (enabled ? 2 : 1))
      #expect(box.writes == (enabled ? 1 : 0))
      #expect(retired.allSatisfy { $0.writes <= 1 })
      retired.append(box)
    }
  }
}

// MARK: - Attempt 012: selectable-row topology churn

extension FrameworkStressTableOutlineTests {
  @Test("stress table outline 012 table navigation skips the currently untagged row")
  func tableOutline012TableNavigationSkipsCurrentlyUntaggedRow() {
    // Hypothesis: Table can retain a departed selection tag when a stable
    // middle row alternates between tagged and read-only forms.
    final class SelectionBox { var value = 1 }
    struct Root: View {
      let middleSelectable: Bool
      let box: SelectionBox
      let tableIdentity: Identity

      var body: some View {
        Table(
          selection: Binding(get: { box.value }, set: { box.value = $0 }),
          columns: [.init("Rows", width: 10)]
        ) {
          TableRow { Text("first") }.tag(1)
          if middleSelectable {
            TableRow { Text("middle-tagged") }.tag(2)
          } else {
            TableRow { Text("middle-read-only") }
          }
          TableRow { Text("last") }.tag(3)
        }
        .id(tableIdentity)
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("TableOutline012")
    let tableIdentity = testIdentity("TableOutline012", "Table")
    let box = SelectionBox()

    for generation in 0..<18 {
      let middleSelectable = generation.isMultiple(of: 2)
      box.value = 1
      let registry = LocalKeyHandlerRegistry()
      _ = renderer.render(
        Root(
          middleSelectable: middleSelectable,
          box: box,
          tableIdentity: tableIdentity
        ),
        context: .init(
          identity: rootIdentity,
          invalidatedIdentities: generation == 0 ? [] : [rootIdentity],
          localKeyHandlerRegistry: registry,
          applyEnvironmentValues: true
        ),
        proposal: .init(width: 18, height: 10)
      )

      #expect(registry.dispatch(identity: tableIdentity, event: .arrowDown))
      #expect(box.value == (middleSelectable ? 2 : 3))
    }
  }
}

// MARK: - Attempt 013: recursively hosted table rows

extension FrameworkStressTableOutlineTests {
  @Test("stress table outline 013 grouped table rows flatten in current authored order")
  func tableOutline013GroupedTableRowsFlattenInCurrentAuthoredOrder() {
    // Hypothesis: recursive table-row collection can reuse the previous Group
    // traversal and strand rows when nested indexed sources reorder.
    struct Item: Identifiable { let id: Int }
    struct Root: View {
      let generation: Int
      let items: [Item]

      var body: some View {
        Table(selection: .constant(2), columns: [.init("Rows", width: 12)]) {
          Group {
            TableRow { Text("start-\(generation)") }.tag(0)
            ForEach(items) { item in
              Group {
                TableRow { Text("item-\(item.id)-g\(generation)") }.tag(item.id)
              }
            }
            Group {
              TableRow { Text("end-\(generation)") }.tag(9)
            }
          }
        }
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("TableOutline013")
    for generation in 0..<18 {
      let ids = generation.isMultiple(of: 2) ? [1, 2, 3] : [3, 1, 2]
      let root = Root(generation: generation, items: ids.map(Item.init(id:)))
      let retained = renderer.render(
        root,
        context: .init(
          identity: identity,
          invalidatedIdentities: generation == 0 ? [] : [identity]
        ),
        proposal: .init(width: 20, height: 12)
      )
      let fresh = DefaultRenderer().render(
        root,
        context: .init(identity: identity),
        proposal: .init(width: 20, height: 12)
      )
      let tokens =
        ["start-\(generation)"]
        + ids.map { "item-\($0)-g\(generation)" }
        + ["end-\(generation)"]
      guard case .table(let payload) = retained.resolvedTree.drawPayload else {
        Issue.record("expected grouped table payload")
        return
      }

      #expect(retained.rasterSurface == fresh.rasterSurface)
      #expect(payload.rows.compactMap { $0.cells.first?.text } == tokens)
    }
  }
}

private struct TableOutlineNode: Identifiable {
  let id: String
  let title: String
  let children: [TableOutlineNode]?

  init(
    id: String,
    title: String,
    children: [TableOutlineNode]? = nil
  ) {
    self.id = id
    self.title = title
    self.children = children
  }
}

// MARK: - Attempt 014: outline child reorder

extension FrameworkStressTableOutlineTests {
  @Test("stress table outline 014 outline child reorder follows current preorder")
  func tableOutline014OutlineChildReorderFollowsCurrentPreorder() {
    // Hypothesis: OutlineTree can reuse a prior recursive child traversal when
    // stable child IDs reorder while their visible payloads also change.
    struct Root: View {
      let nodes: [TableOutlineNode]

      var body: some View {
        OutlineGroup(nodes, children: \.children) { node in
          Text(node.title)
        }
        .outlineStyle(.plain)
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("TableOutline014")
    for generation in 0..<20 {
      let children = [
        TableOutlineNode(id: "a", title: "A-\(generation)"),
        TableOutlineNode(id: "b", title: "B-\(generation)"),
        TableOutlineNode(id: "c", title: "C-\(generation)"),
      ]
      let ordered =
        generation.isMultiple(of: 2) ? children : [children[2], children[0], children[1]]
      let root = Root(
        nodes: [
          .init(id: "root", title: "Root-\(generation)", children: ordered)
        ]
      )
      let retained = renderer.render(
        root,
        context: .init(
          identity: identity,
          invalidatedIdentities: generation == 0 ? [] : [identity]
        ),
        proposal: .init(width: 24, height: 10)
      )
      let fresh = DefaultRenderer().render(
        root,
        context: .init(identity: identity),
        proposal: .init(width: 24, height: 10)
      )
      let expected = ["Root-\(generation)"] + ordered.map(\.title)

      #expect(retained.rasterSurface == fresh.rasterSurface)
      #expect(tableOutlineContainsInOrder(expected, in: tableOutlineText(retained)))
    }
  }
}

// MARK: - Attempt 015: outline child cardinality churn

extension FrameworkStressTableOutlineTests {
  @Test("stress table outline 015 outline zero to many children leaves no phantom branches")
  func tableOutline015OutlineZeroToManyChildrenLeavesNoPhantomBranches() {
    // Hypothesis: recursive indexed sources can retain departed child rows or
    // connector metadata when one parent crosses between leaf and branch forms.
    struct Root: View {
      let generation: Int
      let childCount: Int

      var body: some View {
        OutlineGroup(
          [
            TableOutlineNode(
              id: "root",
              title: "root-\(generation)",
              children: childCount == 0
                ? nil
                : (0..<childCount).map {
                  .init(id: "leaf-\($0)", title: "leaf-\($0)-g\(generation)")
                }
            )
          ],
          children: \.children
        ) { node in
          Text(node.title)
        }
        .outlineStyle(.rounded)
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("TableOutline015")
    for generation in 0..<18 {
      let count = generation.isMultiple(of: 2) ? 0 : 7
      let root = Root(generation: generation, childCount: count)
      let retained = renderer.render(
        root,
        context: .init(
          identity: identity,
          invalidatedIdentities: generation == 0 ? [] : [identity]
        ),
        proposal: .init(width: 26, height: 12)
      )
      let fresh = DefaultRenderer().render(
        root,
        context: .init(identity: identity),
        proposal: .init(width: 26, height: 12)
      )
      let rendered = tableOutlineText(retained)

      #expect(retained.rasterSurface == fresh.rasterSurface)
      #expect(retained.semanticSnapshot == fresh.semanticSnapshot)
      #expect(rendered.contains("leaf-0-g\(generation)") == (count > 0))
      #expect(rendered.contains("leaf-6-g\(generation)") == (count > 0))
    }
  }
}

// MARK: - Attempt 016: outline node reparenting

extension FrameworkStressTableOutlineTests {
  @Test("stress table outline 016 reparented outline node follows its current ancestry")
  func tableOutline016ReparentedOutlineNodeFollowsCurrentAncestry() {
    // Hypothesis: the recursive entity route can keep a stable leaf under its
    // former parent after the same ID moves to another outline branch.
    struct Root: View {
      let nodes: [TableOutlineNode]

      var body: some View {
        OutlineGroup(nodes, children: \.children) { node in
          Text(node.title)
        }
        .outlineStyle(.ascii)
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("TableOutline016")
    for generation in 0..<20 {
      let leaf = TableOutlineNode(id: "leaf", title: "leaf-\(generation)")
      let underLeft = generation.isMultiple(of: 2)
      let nodes = [
        TableOutlineNode(
          id: "left",
          title: "left-\(generation)",
          children: underLeft ? [leaf] : nil
        ),
        TableOutlineNode(
          id: "right",
          title: "right-\(generation)",
          children: underLeft ? nil : [leaf]
        ),
      ]
      let root = Root(nodes: nodes)
      let retained = renderer.render(
        root,
        context: .init(
          identity: identity,
          invalidatedIdentities: generation == 0 ? [] : [identity]
        ),
        proposal: .init(width: 26, height: 8)
      )
      let fresh = DefaultRenderer().render(
        root,
        context: .init(identity: identity),
        proposal: .init(width: 26, height: 8)
      )
      let expected =
        underLeft
        ? ["left-\(generation)", "leaf-\(generation)", "right-\(generation)"]
        : ["left-\(generation)", "right-\(generation)", "leaf-\(generation)"]

      #expect(retained.rasterSurface == fresh.rasterSurface)
      #expect(tableOutlineContainsInOrder(expected, in: tableOutlineText(retained)))
    }
  }
}

// MARK: - Attempt 017: outline root-subtree reorder

extension FrameworkStressTableOutlineTests {
  @Test("stress table outline 017 reordered roots carry their current subtrees")
  func tableOutline017ReorderedRootsCarryCurrentSubtrees() {
    // Hypothesis: root entity reordering can move only the parent row while a
    // retained descendant traversal remains at the old structural slot.
    struct Root: View {
      let nodes: [TableOutlineNode]

      var body: some View {
        OutlineGroup(nodes, children: \.children) { Text($0.title) }
          .outlineStyle(.rounded)
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("TableOutline017")
    for generation in 0..<20 {
      let a = TableOutlineNode(
        id: "a",
        title: "A-\(generation)",
        children: [.init(id: "a1", title: "A1-\(generation)")]
      )
      let b = TableOutlineNode(
        id: "b",
        title: "B-\(generation)",
        children: [.init(id: "b1", title: "B1-\(generation)")]
      )
      let nodes = generation.isMultiple(of: 2) ? [a, b] : [b, a]
      let expected =
        generation.isMultiple(of: 2)
        ? ["A-\(generation)", "A1-\(generation)", "B-\(generation)", "B1-\(generation)"]
        : ["B-\(generation)", "B1-\(generation)", "A-\(generation)", "A1-\(generation)"]
      let root = Root(nodes: nodes)
      let retained = renderer.render(
        root,
        context: .init(
          identity: identity,
          invalidatedIdentities: generation == 0 ? [] : [identity]
        ),
        proposal: .init(width: 24, height: 10)
      )
      let fresh = DefaultRenderer().render(
        root,
        context: .init(identity: identity),
        proposal: .init(width: 24, height: 10)
      )

      #expect(retained.rasterSurface == fresh.rasterSurface)
      #expect(tableOutlineContainsInOrder(expected, in: tableOutlineText(retained)))
    }
  }
}

// MARK: - Attempt 018: outline child identity replacement

extension FrameworkStressTableOutlineTests {
  @Test("stress table outline 018 replaced outline child removes departed identity")
  func tableOutline018ReplacedOutlineChildRemovesDepartedIdentity() {
    // Hypothesis: a constant-cardinality recursive slot can reuse the departed
    // child's resolved node after its entity ID and visible payload both change.
    struct Root: View {
      let generation: Int

      var body: some View {
        OutlineGroup(
          [
            TableOutlineNode(
              id: "root",
              title: "root-g\(generation)",
              children: [
                .init(
                  id: generation.isMultiple(of: 2) ? "child-a" : "child-b",
                  title: "child-\(generation.isMultiple(of: 2) ? "a" : "b")-g\(generation)"
                )
              ]
            )
          ],
          children: \.children
        ) { Text($0.title) }
        .outlineStyle(.plain)
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("TableOutline018")
    for generation in 0..<20 {
      let root = Root(generation: generation)
      let retained = renderer.render(
        root,
        context: .init(
          identity: identity,
          invalidatedIdentities: generation == 0 ? [] : [identity]
        ),
        proposal: .init(width: 26, height: 10)
      )
      let fresh = DefaultRenderer().render(
        root,
        context: .init(identity: identity),
        proposal: .init(width: 26, height: 10)
      )
      let rendered = tableOutlineText(retained)
      let currentKind = generation.isMultiple(of: 2) ? "a" : "b"

      #expect(retained.rasterSurface == fresh.rasterSurface)
      #expect(retained.semanticSnapshot == fresh.semanticSnapshot)
      #expect(rendered.contains("child-\(currentKind)-g\(generation)"))
      if generation > 0 {
        #expect(!rendered.contains("g\(generation - 1)"))
      }
    }
  }
}

// MARK: - Attempt 019: outline depth contraction and expansion

extension FrameworkStressTableOutlineTests {
  @Test("stress table outline 019 outline depth replacement removes departed ancestry")
  func tableOutline019OutlineDepthReplacementRemovesDepartedAncestry() {
    // Hypothesis: contracting a retained recursive path can leave a departed
    // intermediate node or give the surviving leaf its old indentation depth.
    struct Root: View {
      let nodes: [TableOutlineNode]

      var body: some View {
        OutlineGroup(nodes, children: \.children) { Text($0.title) }
          .outlineStyle(.ascii)
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("TableOutline019")
    for generation in 0..<21 {
      let leaf = TableOutlineNode(id: "leaf", title: "leaf-\(generation)")
      let nodes: [TableOutlineNode]
      switch generation % 3 {
      case 0:
        nodes = [
          .init(
            id: "root",
            title: "root-\(generation)",
            children: [
              .init(id: "middle", title: "middle-\(generation)", children: [leaf])
            ]
          )
        ]
      case 1:
        nodes = [
          .init(id: "root", title: "root-\(generation)", children: [leaf])
        ]
      default:
        nodes = [leaf]
      }
      let root = Root(nodes: nodes)
      let retained = renderer.render(
        root,
        context: .init(
          identity: identity,
          invalidatedIdentities: generation == 0 ? [] : [identity]
        ),
        proposal: .init(width: 28, height: 8)
      )
      let fresh = DefaultRenderer().render(
        root,
        context: .init(identity: identity),
        proposal: .init(width: 28, height: 8)
      )
      let rendered = tableOutlineText(retained)

      #expect(retained.rasterSurface == fresh.rasterSurface)
      #expect(rendered.contains("leaf-\(generation)"))
      #expect(rendered.contains("middle-") == (generation % 3 == 0))
      #expect(rendered.contains("root-") == (generation % 3 != 2))
    }
  }
}

// MARK: - Attempt 020: live outline-style replacement

extension FrameworkStressTableOutlineTests {
  @Test("stress table outline 020 outline connectors follow the current style")
  func tableOutline020OutlineConnectorsFollowCurrentStyle() {
    // Hypothesis: OutlineTree can retain connector draw payloads from the
    // previous environment style even while row text resolves freshly.
    struct Root: View {
      let style: AnyOutlineStyle
      let generation: Int

      var body: some View {
        OutlineGroup(
          [
            TableOutlineNode(
              id: "root",
              title: "root-\(generation)",
              children: [.init(id: "leaf", title: "leaf-\(generation)")]
            )
          ],
          children: \.children
        ) { Text($0.title) }
        .outlineStyle(style)
      }
    }

    let variants: [(AnyOutlineStyle, String)] = [
      (.rounded, "╰─"),
      (.plain, "└─"),
      (.ascii, "`-"),
    ]
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("TableOutline020")
    for generation in 0..<21 {
      let variant = variants[generation % variants.count]
      let root = Root(style: variant.0, generation: generation)
      let retained = renderer.render(
        root,
        context: .init(
          identity: identity,
          invalidatedIdentities: generation == 0 ? [] : [identity]
        ),
        proposal: .init(width: 24, height: 5)
      )
      let fresh = DefaultRenderer().render(
        root,
        context: .init(identity: identity),
        proposal: .init(width: 24, height: 5)
      )
      let rendered = tableOutlineText(retained)

      #expect(retained.rasterSurface == fresh.rasterSurface)
      #expect(rendered.contains("\(variant.1) leaf-\(generation)"))
    }
  }
}

// MARK: - Attempt 021: outline row-style freshness

extension FrameworkStressTableOutlineTests {
  @Test("stress table outline 021 outline row builder publishes current text style")
  func tableOutline021OutlineRowBuilderPublishesCurrentTextStyle() {
    // Hypothesis: the captured recursive row builder can redraw current text
    // while retaining style metadata from an earlier same-ID node generation.
    struct Root: View {
      let generation: Int

      var body: some View {
        OutlineGroup(
          [
            TableOutlineNode(
              id: "root",
              title: "root-\(generation)",
              children: [.init(id: "leaf", title: "leaf-\(generation)")]
            )
          ],
          children: \.children
        ) { node in
          Text(node.title)
            .foregroundStyle(generation.isMultiple(of: 2) ? Color.red : .cyan)
            .bold(generation % 3 == 0)
        }
        .outlineStyle(.plain)
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("TableOutline021")
    for generation in 0..<21 {
      let root = Root(generation: generation)
      let retained = renderer.render(
        root,
        context: .init(
          identity: identity,
          invalidatedIdentities: generation == 0 ? [] : [identity]
        ),
        proposal: .init(width: 24, height: 5)
      )
      let fresh = DefaultRenderer().render(
        root,
        context: .init(identity: identity),
        proposal: .init(width: 24, height: 5)
      )

      #expect(retained.rasterSurface == fresh.rasterSurface)
      #expect(tableOutlineText(retained).contains("leaf-\(generation)"))
    }
  }
}

// MARK: - Attempt 022: outline List navigation after root reorder

extension FrameworkStressTableOutlineTests {
  @Test("stress table outline 022 outline list navigation follows current preorder")
  func tableOutline022OutlineListNavigationFollowsCurrentPreorder() {
    // Hypothesis: List can refresh flattened outline rows but retain the prior
    // selectable-tag order in its key handler after root subtrees reorder.
    final class SelectionBox { var value = "a" }
    struct Root: View {
      let nodes: [TableOutlineNode]
      let box: SelectionBox
      let listIdentity: Identity

      var body: some View {
        List(
          nodes,
          selection: Binding(get: { box.value }, set: { box.value = $0 }),
          children: \.children
        ) { node in
          Text(node.title)
        }
        .id(listIdentity)
        .frame(width: 22, height: 10, alignment: .topLeading)
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("TableOutline022")
    let listIdentity = testIdentity("TableOutline022", "List")
    let box = SelectionBox()
    var environment = EnvironmentValues()
    environment.focusedIdentity = listIdentity

    for generation in 0..<18 {
      let a = TableOutlineNode(
        id: "a",
        title: "A",
        children: [.init(id: "a1", title: "A1")]
      )
      let b = TableOutlineNode(
        id: "b",
        title: "B",
        children: [.init(id: "b1", title: "B1")]
      )
      let nodes = generation.isMultiple(of: 2) ? [a, b] : [b, a]
      box.value = nodes[0].id
      let registry = LocalKeyHandlerRegistry()
      _ = renderer.render(
        Root(nodes: nodes, box: box, listIdentity: listIdentity),
        context: .init(
          identity: rootIdentity,
          environmentValues: environment,
          invalidatedIdentities: generation == 0 ? [] : [rootIdentity],
          localKeyHandlerRegistry: registry,
          applyEnvironmentValues: true
        ),
        proposal: .init(width: 22, height: 10)
      )

      #expect(registry.dispatch(identity: listIdentity, event: .arrowDown))
      #expect(box.value == nodes[0].children?.first?.id)
    }
  }
}

// MARK: - Attempt 023: selected outline node reparenting

extension FrameworkStressTableOutlineTests {
  @Test("stress table outline 023 selected outline node follows reparented geometry")
  func tableOutline023SelectedOutlineNodeFollowsReparentedGeometry() {
    // Hypothesis: List selection geometry can stay at a leaf's former flattened
    // row when that stable node moves between outline parents.
    struct Root: View {
      let nodes: [TableOutlineNode]
      let listIdentity: Identity

      var body: some View {
        List(nodes, selection: .constant("leaf"), children: \.children) { node in
          Text(node.title)
        }
        .id(listIdentity)
        .listStyle(.plain)
        .frame(width: 24, height: 9, alignment: .topLeading)
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("TableOutline023")
    let listIdentity = testIdentity("TableOutline023", "List")
    var environment = EnvironmentValues()
    environment.focusedIdentity = listIdentity

    for generation in 0..<20 {
      let leaf = TableOutlineNode(id: "leaf", title: "selected-leaf-\(generation)")
      let underLeft = generation.isMultiple(of: 2)
      let nodes = [
        TableOutlineNode(id: "left", title: "left", children: underLeft ? [leaf] : nil),
        TableOutlineNode(id: "right", title: "right", children: underLeft ? nil : [leaf]),
      ]
      let root = Root(nodes: nodes, listIdentity: listIdentity)
      let retained = renderer.render(
        root,
        context: .init(
          identity: rootIdentity,
          environmentValues: environment,
          invalidatedIdentities: generation == 0 ? [] : [rootIdentity],
          applyEnvironmentValues: true
        ),
        proposal: .init(width: 24, height: 9)
      )
      let fresh = DefaultRenderer().render(
        root,
        context: .init(
          identity: rootIdentity,
          environmentValues: environment,
          applyEnvironmentValues: true
        ),
        proposal: .init(width: 24, height: 9)
      )
      let selectedLine = retained.rasterSurface.lines.first { $0.contains("▌") }

      #expect(retained.rasterSurface == fresh.rasterSurface)
      #expect(selectedLine?.contains("selected-leaf-\(generation)") == true)
    }
  }
}

// MARK: - Attempt 024: outline row action freshness

extension FrameworkStressTableOutlineTests {
  @Test("stress table outline 024 outline row button dispatches its current closure")
  func tableOutline024OutlineRowButtonDispatchesCurrentClosure() throws {
    // Hypothesis: recursively hosted row content can redraw a current Button
    // label while restoring the action closure from the first outline generation.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("TableOutline024"),
      size: .init(width: 34, height: 9)
    ) {
      TableOutline024Fixture()
    }
    defer { harness.shutdown() }

    for generation in 1...8 {
      _ = try harness.clickText("Advance outline")
      #expect(harness.frame.contains("Leaf action \(generation)"))
      let frame = try harness.clickText("Leaf action \(generation)")
      #expect(frame.contains("fired \(generation)"))
    }
  }
}

@MainActor
private struct TableOutline024Fixture: View {
  @State private var generation = 0
  @State private var fired = -1

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Advance outline") { generation += 1 }
      Text("fired \(fired)")
      OutlineGroup(
        [
          TableOutlineNode(
            id: "root",
            title: "Root",
            children: [.init(id: "leaf", title: "Leaf action \(generation)")]
          )
        ],
        children: \.children
      ) { node in
        Button(node.title) { fired = generation }
      }
      .outlineStyle(.plain)
    }
  }
}

// MARK: - Attempt 025: outline row state under reorder

extension FrameworkStressTableOutlineTests {
  @Test("stress table outline 025 stable outline row state follows reordered identity")
  func tableOutline025StableOutlineRowStateFollowsReorderedIdentity() throws {
    // Hypothesis: OutlineTree can key row-local state by recursive structural
    // slot instead of the stable node ID when root rows exchange order.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("TableOutline025"),
      size: .init(width: 36, height: 8)
    ) {
      TableOutline025Fixture()
    }
    defer { harness.shutdown() }

    for expectedCount in 0..<8 {
      let incremented = try harness.clickText("A count \(expectedCount)")
      #expect(incremented.contains("A count \(expectedCount + 1)"))
      let reordered = try harness.clickText("Reverse outline roots")
      #expect(reordered.contains("A count \(expectedCount + 1)"))
      #expect(reordered.contains("B count 0"))
    }
  }
}

@MainActor
private struct TableOutline025Fixture: View {
  @State private var reversed = false

  private var nodes: [TableOutlineNode] {
    let values = [
      TableOutlineNode(id: "a", title: "A"),
      TableOutlineNode(id: "b", title: "B"),
    ]
    return reversed ? Array(values.reversed()) : values
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Reverse outline roots") { reversed.toggle() }
      OutlineGroup(nodes, children: \.children) { node in
        TableOutline025Row(title: node.title)
      }
      .outlineStyle(.plain)
    }
  }
}

@MainActor
private struct TableOutline025Row: View {
  let title: String
  @State private var count = 0

  var body: some View {
    Button("\(title) count \(count)") { count += 1 }
  }
}
