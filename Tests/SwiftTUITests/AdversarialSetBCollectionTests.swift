// Adversarial set B, pass 2: collections and selection controls (181–190).
//
// Lists, tables, outlines and pickers flatten authored rows into payloads
// and step selection over tag lists. The probes here put structure the
// flattening does not model (a section inside a section, a row with more
// cells than columns, a zero-column table, an expandable node with no
// children), selection states the stepper does not model (a disabled or
// duplicate current option, a disabled row, an absent tag) and the
// multi-selection paint seam that only knows one row.
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("Adversarial set B: collections", .serialized)
struct AdversarialSetBCollectionTests {
  private func render<V: View>(_ view: V, _ name: String, width: Int = 30, height: Int = 10)
    -> RenderSnapshot
  {
    DefaultRenderer().render(
      view, context: .init(identity: testIdentity("SetBCollections", name)),
      proposal: .init(width: width, height: height))
  }

  // A Section nested inside a List section keeps its rows as rows.
  @Test func setB181NestedSectionsKeepTheirRows() {
    let snapshot = render(
      List {
        Section("Outer") {
          Section("Inner") {
            Text("One")
            Text("Two")
          }
        }
      }, "nestedSections")
    let items = snapshot.semanticSnapshot.accessibilityNodes.filter {
      $0.role == .custom("listitem")
    }
    let lines = snapshot.rasterSurface.lines
    #expect(lines.contains { $0.contains("Two") && !$0.contains("One") }, "\(lines)")
    do {
      #expect(items.count == 2, "\(items.map(\.label))")
      #expect(lines.contains { $0.contains("One") && !$0.contains("Two") }, "\(lines)")
      #expect(lines.contains { $0.contains("Inner") }, "\(lines)")
    }
  }

  @Test(arguments: [false, true])
  func nestedSectionsKeepDirectRowsInTheirOwnSection(outerHeader: Bool) {
    let snapshot = render(
      List {
        Section {
          Text("Before")
          Section("Inner") {
            Text("One")
            Text("Two")
          }
          Text("After")
        } header: {
          if outerHeader { Text("Outer") }
        }
      }, "mixedNestedSections", height: 20)
    let descriptions = snapshot.semanticSnapshot.accessibilityNodes.filter {
      $0.role == .custom("listitem")
    }.compactMap { $0.properties.description }
    let outer = outerHeader ? "Outer" : "Section"
    #expect(
      descriptions == [
        "\(outer), item 1 of 2", "Inner, item 1 of 2",
        "Inner, item 2 of 2", "\(outer), item 2 of 2",
      ])
  }

  // Every member of a multi-selection table is painted selected, not only
  // the row that holds the keyboard cursor.
  @Test func setB182MultiSelectionTablePaintsEveryMember() throws {
    let tableIdentity = testIdentity("SetBCollections", "multiTable")
    let probe = SetBSetProbe([1, 3])
    func table() -> some View {
      Table(
        [1, 2, 3], id: \.self, selection: probe.binding(), columns: [TableColumn("Name", width: 8)]
      ) {
        row in
        Text("row\(row)")
      }
      .id(tableIdentity)
    }
    // Selected chrome paints only while the table is focused: focus its own
    // region, whichever identity the semantics publish for it.
    let unfocused = DefaultRenderer().render(
      table(), context: .init(identity: testIdentity("SetBCollections", "multiTableRoot")),
      proposal: .init(width: 30, height: 10))
    let region = try #require(unfocused.semanticSnapshot.focusRegions.first?.identity)
    var environment = EnvironmentValues()
    environment.focusedIdentity = region
    let snapshot = DefaultRenderer().render(
      table(),
      context: .init(
        identity: testIdentity("SetBCollections", "multiTableRoot"), environmentValues: environment,
        applyEnvironmentValues: true),
      proposal: .init(width: 30, height: 10))
    let lines = snapshot.rasterSurface.lines
    func style(ofRow row: Int) throws -> ResolvedTextStyle? {
      let y = try #require(lines.firstIndex { $0.contains("row\(row)") }, "row\(row) in \(lines)")
      let x = try #require(lines[y].firstRange(of: "row\(row)")).lowerBound
      let column = lines[y].distance(from: lines[y].startIndex, to: x)
      return snapshot.rasterSurface.cells[y][column].style
    }
    let first = try style(ofRow: 1)
    let second = try style(ofRow: 2)
    let third = try style(ofRow: 3)
    #expect(first == third, "both members share the selected paint")
    do {
      #expect(
        first != second,
        "member row 1 is painted differently from non-member row 2")
      #expect(
        third != second,
        "member row 3 is painted differently from non-member row 2")
    }
    let selectors = snapshot.semanticSnapshot.accessibilityNodes.filter {
      $0.label?.hasPrefix("Select row") == true
    }
    let selected = selectors.filter { $0.control?.value == .boolean(true) }.compactMap(\.label)
    #expect(selected.sorted() == ["Select row 1", "Select row 3"], "\(selected)")
  }

  // Stepping from a disabled current option skips in the pressed direction:
  // Down from a disabled middle option reaches the next enabled one, Up the
  // previous one.
  @Test func setB183PickerStepsPastADisabledCurrentOptionInThePressedDirection() {
    let pickerIdentity = testIdentity("SetBCollections", "disabledCurrent")
    let selection = SetBValueBox(1)
    let registry = LocalKeyHandlerRegistry()
    var environment = EnvironmentValues()
    environment.focusedIdentity = pickerIdentity
    _ = DefaultRenderer().render(
      Picker("Mode", selection: selection.binding()) {
        Text("A").tag(0)
        Text("B").disabled(true).tag(1)
        Text("C").tag(2)
      }
      .id(pickerIdentity).pickerStyle(.inline),
      context: .init(
        identity: testIdentity("SetBCollections", "disabledCurrentRoot"),
        environmentValues: environment, localKeyHandlerRegistry: registry,
        applyEnvironmentValues: true),
      proposal: .init(width: 30, height: 8))
    #expect(registry.dispatch(identity: pickerIdentity, keyPress: KeyPress(.arrowDown)))
    let afterDown = selection.value
    selection.value = 1
    #expect(registry.dispatch(identity: pickerIdentity, keyPress: KeyPress(.arrowUp)))
    let afterUp = selection.value
    do {
      #expect(afterDown == 2, "Down from B lands on C, got \(afterDown)")
      #expect(afterUp == 0, "Up from B lands on A, got \(afterUp)")
    }
  }

  // Duplicate tags are a single option for stepping: Down from the first
  // occurrence reaches the next distinct tag.
  @Test func setB184PickerStepsPastDuplicateTags() {
    let pickerIdentity = testIdentity("SetBCollections", "duplicateTags")
    let selection = SetBValueBox(1)
    let registry = LocalKeyHandlerRegistry()
    var environment = EnvironmentValues()
    environment.focusedIdentity = pickerIdentity
    _ = DefaultRenderer().render(
      Picker("Mode", selection: selection.binding()) {
        Text("A").tag(1)
        Text("B").tag(1)
        Text("C").tag(2)
      }
      .id(pickerIdentity).pickerStyle(.inline),
      context: .init(
        identity: testIdentity("SetBCollections", "duplicateTagsRoot"),
        environmentValues: environment, localKeyHandlerRegistry: registry,
        applyEnvironmentValues: true),
      proposal: .init(width: 30, height: 8))
    _ = registry.dispatch(identity: pickerIdentity, keyPress: KeyPress(.arrowDown))
    if selection.value == 1 {
      _ = registry.dispatch(identity: pickerIdentity, keyPress: KeyPress(.arrowDown))
    }
    do {
      #expect(selection.value == 2, "two Downs from the duplicate reach C, got \(selection.value)")
    }
  }

  // Keyboard selection skips a disabled row and Return never activates one.
  @Test(arguments: [false, true])
  func setB185DisabledListRowsAreNeitherSelectedNorActivated(indexed: Bool) throws {
    let probe = SetBActivationProbe()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("SetBCollections", "disabledRows"),
      size: .init(width: 40, height: 10)
    ) {
      SetBDisabledRowList(probe: probe, indexed: indexed)
    }
    defer { h.shutdown() }
    _ = try h.focusText("A")
    _ = try h.pressKey(KeyPress(.arrowDown))
    let afterDown = h.frame
    _ = try h.clickText("Select B")
    try #require(h.frame.contains("sel=2"), "\(h.frame)")
    // B has no interactive row target. Its frame focuses the explicitly
    // focusable list, whose selected value is still B after an external write.
    let listIdentity = try #require(h.runLoop.latestSemanticSnapshot.scrollRoutes.first?.identity)
    _ = try h.focus(listIdentity)
    #expect(h.frame.contains("sel=2"), "focus preserves disabled selection: \(h.frame)")
    _ = try h.pressKey(KeyPress(.return))
    do {
      #expect(afterDown.contains("sel=3"), "Down from A skips disabled B: \(afterDown)")
      #expect(probe.activated.isEmpty, "Return on a disabled row activated \(probe.activated)")
    }
  }

  // An element whose children are an empty array is an expandable node with
  // nothing inside; only a nil children value is a leaf.
  @Test func setB186OutlineEmptyChildrenIsAnExpandableNodeNotALeaf() {
    let snapshot = render(
      OutlineGroup(
        [SetBNode(id: 1, children: []), SetBNode(id: 2, children: nil)], id: \.id,
        children: \.children
      ) { node in
        Text("n\(node.id)")
      }, "outlineEmpty", width: 30, height: 6)
    let nodes = snapshot.semanticSnapshot.accessibilityNodes
    let expandable = nodes.filter { $0.properties?.expanded != nil }
    let lines = snapshot.rasterSurface.lines
    let one = lines.first { $0.contains("n1") } ?? ""
    let two = lines.first { $0.contains("n2") } ?? ""
    #expect(lines.contains { $0.contains("n2") }, "\(lines)")
    do {
      #expect(expandable.count == 1, "\(nodes.map { ($0.label, $0.properties?.expanded) })")
      #expect(expandable.first?.label?.contains("1") == true, "\(expandable.map(\.label))")
      #expect(
        one.prefix(while: { $0 != "n" }) != two.prefix(while: { $0 != "n" }),
        "the expandable row carries a disclosure indicator: \(lines)")
    }
  }

  // A row with more cells than the table has columns drops the surplus
  // instead of leaking an extra cell past the last column.
  @Test func setB187SurplusRowCellsDoNotLeakPastTheLastColumn() {
    let snapshot = render(
      Table(columns: [TableColumn("A", width: 4)]) {
        TableRow {
          Text("a1")
          Text("EXTRA")
        }
      }, "surplusCells", width: 20, height: 6)
    let cells = snapshot.semanticSnapshot.accessibilityNodes.filter { $0.role == .cell }
    let columnIndices = cells.compactMap { $0.properties?.columnIndex }
    let joined = snapshot.rasterSurface.lines.joined(separator: "\n")
    #expect(!joined.contains("EX"), "\(snapshot.rasterSurface.lines)")
    #expect(joined.contains("a1"), "\(snapshot.rasterSurface.lines)")
    do {
      #expect(columnIndices.allSatisfy { $0 <= 1 }, "\(columnIndices)")
    }
  }

  // A table with no columns neither traps nor paints the cells of its rows.
  @Test func setB188ZeroColumnTableHostsNothing() {
    let snapshot = render(
      Table(columns: []) {
        TableRow { Text("x") }
      }, "zeroColumns", width: 20, height: 6)
    let joined = snapshot.rasterSurface.lines.joined(separator: "\n")
    let cells = snapshot.semanticSnapshot.accessibilityNodes.filter { $0.role == .cell }
    do {
      #expect(!joined.contains("x"), "\(snapshot.rasterSurface.lines)")
      #expect(
        snapshot.measuredTree.measuredSize.width <= 2, "\(snapshot.measuredTree.measuredSize)")
      #expect(cells.isEmpty, "\(cells.map(\.label))")
    }
  }

  // A selection holding a tag absent from the data does not strand the
  // keyboard: arrows step relative to the focused row and write a real tag.
  @Test func setB189AbsentSelectionTagStepsRelativeToTheFocusedRow() throws {
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("SetBCollections", "absentTag"), size: .init(width: 40, height: 10)
    ) {
      SetBAbsentTagList()
    }
    defer { h.shutdown() }
    try #require(h.frame.contains("sel=99"), "\(h.frame)")
    _ = try h.focusText("A")
    _ = try h.pressKey(KeyPress(.arrowDown))
    #expect(
      h.frame.contains("sel=2"), "Down from the focused first row selects the second: \(h.frame)")
    _ = try h.clickText("Reset")
    try #require(h.frame.contains("sel=99"), "\(h.frame)")
    _ = try h.focusText("B")
    _ = try h.pressKey(KeyPress(.arrowUp))
    #expect(
      h.frame.contains("sel=1"), "Up from the focused second row selects the first: \(h.frame)")
    _ = try h.clickText("Reset")
    try #require(h.frame.contains("sel=99"), "\(h.frame)")
    _ = try h.focusText("A")
    _ = try h.pressKey(KeyPress(.arrowUp))
    #expect(!h.frame.contains("sel=99"), "Up at the top still writes a real tag: \(h.frame)")
  }

  // `.disabled(false)` inside `.disabled(true)` stays disabled: the flag
  // composes with AND down the environment.
  @Test func setB190NestedDisabledFalseCannotReEnable() throws {
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("SetBCollections", "nestedDisabled"),
      size: .init(width: 30, height: 5)
    ) {
      SetBNestedDisabledFixture()
    }
    defer { h.shutdown() }
    let node = try #require(
      h.runLoop.publishedAccessibilitySnapshot.accessibilityNodes.first { $0.label == "Go" })
    #expect(!node.isEnabled)
    _ = try h.clickText("Go")
    #expect(h.frame.contains("n=0"), "\(h.frame)")
    #expect(h.focusRegionCount == 0, "a disabled control has no focus region")
  }
}

@MainActor
private final class SetBValueBox<Value> {
  var value: Value
  init(_ value: Value) { self.value = value }
  func binding() -> Binding<Value> {
    Binding(get: { self.value }, set: { self.value = $0 })
  }
}

@MainActor
private final class SetBSetProbe {
  var members: Set<Int>
  init(_ members: Set<Int>) { self.members = members }
  func binding() -> Binding<Set<Int>> {
    Binding(get: { self.members }, set: { self.members = $0 })
  }
}

@MainActor
private final class SetBActivationProbe {
  var activated: [Int] = []
}

private struct SetBNode: Identifiable, Sendable {
  let id: Int
  var children: [SetBNode]?
}

private struct SetBDisabledRowList: View {
  let probe: SetBActivationProbe
  let indexed: Bool
  @State private var selection: Int? = 1

  var body: some View {
    VStack(alignment: .leading) {
      if indexed {
        List(
          [1, 2, 3], id: \.self, selection: $selection, onActivate: { probe.activated.append($0) }
        ) { row in
          Text(row == 1 ? "A" : row == 2 ? "B" : "C").disabled(row == 2)
        }
        .focusable().frame(height: 5)
      } else {
        List(selection: $selection, onActivate: { probe.activated.append($0) }) {
          Text("A").tag(1)
          Text("B").tag(2).disabled(true)
          Text("C").tag(3)
        }
        .focusable().frame(height: 5)
      }
      Button("Select B") { selection = 2 }
      Text("sel=\(selection.map(String.init) ?? "nil")")
    }
  }
}

private struct SetBAbsentTagList: View {
  @State private var selection: Int? = 99

  var body: some View {
    VStack(alignment: .leading) {
      List(selection: $selection) {
        Text("A").tag(1)
        Text("B").tag(2)
      }
      .frame(height: 4)
      Button("Reset") { selection = 99 }
      Text("sel=\(selection.map(String.init) ?? "nil")")
    }
  }
}

private struct SetBNestedDisabledFixture: View {
  @State private var n = 0

  var body: some View {
    VStack(alignment: .leading) {
      Button("Go") { n += 1 }.disabled(false)
      Text("n=\(n)")
    }
    .disabled(true)
  }
}
