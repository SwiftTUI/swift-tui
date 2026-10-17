import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

// STUI-611, STUI-681, STUI-693, STUI-928, STUI-935 and STUI-952–954:
// compose mutations with actual RunLoop input and inspect the committed frame.
@MainActor
@Suite("Adversarial set A: composed runtime", .serialized)
struct AdversarialSetARuntimeTests {
  @Test func setA081DisclosureRoundTripKeepsAllSiblings() throws {
    let h = try disclosure()
    defer { h.shutdown() }
    for _ in 0..<3 {
      try key("o", in: h)
      #expect(!h.frame.contains("leaf-A"))
      try key("o", in: h)
      for label in ["leaf-A", "leaf-B", "leaf-C", "nested-leaf", "tail"] {
        #expect(h.frame.contains(label), "\(h.frame)")
      }
    }
  }

  @Test func setA082NestedDisclosureBindingSurvivesOuterChurn() throws {
    let h = try disclosure()
    defer { h.shutdown() }
    try key("n", in: h)
    try key("o", in: h)
    try key("o", in: h)
    #expect(!h.frame.contains("nested-leaf"))
    #expect(h.frame.contains("Inner"))
    try key("n", in: h)
    #expect(h.frame.contains("nested-leaf"))
  }

  @Test func setA083DisclosureBranchSwapDoesNotDropFollowingChildren() throws {
    let h = try disclosure()
    defer { h.shutdown() }
    try key("b", in: h)
    #expect(h.frame.contains("branch-new-1"))
    #expect(h.frame.contains("branch-new-2"))
    #expect(!h.frame.contains("branch-old"))
    #expect(h.frame.contains("tail"))
    try key("b", in: h)
    #expect(h.frame.contains("branch-old"))
    #expect(!h.frame.contains("branch-new-2"))
  }

  @Test func setA084DisclosureChildActionDoesNotToggleAncestor() throws {
    let h = try disclosure()
    defer { h.shutdown() }
    try h.clickText("Child action")
    #expect(h.frame.contains("calls=1"))
    #expect(h.frame.contains("leaf-A"))
    #expect(h.frame.contains("nested-leaf"))
    try h.clickText("Child action")
    #expect(h.frame.contains("calls=2"))
  }

  @Test func setA085DisclosureReorderedChildrenKeepEverySlot() throws {
    let h = try disclosure()
    defer { h.shutdown() }
    try key("r", in: h)
    let lines = h.frame.split(whereSeparator: \.isNewline)
    let a = try #require(lines.firstIndex { $0.contains("leaf-A") })
    let b = try #require(lines.firstIndex { $0.contains("leaf-B") })
    let c = try #require(lines.firstIndex { $0.contains("leaf-C") })
    #expect(c < b && b < a)
    try h.clickText("Child action")
    #expect(h.frame.contains("calls=1"))
  }

  @Test func setA086DisclosureEmptyBranchCanRepopulate() throws {
    let h = try disclosure()
    defer { h.shutdown() }
    try key("e", in: h)
    #expect(!h.frame.contains("leaf-A"))
    #expect(h.frame.contains("tail"))
    try key("e", in: h)
    #expect(h.frame.contains("leaf-A"))
    #expect(h.frame.contains("leaf-C"))
    #expect(h.frame.contains("tail"))
  }

  @Test func setA087DisclosureMultilineGrowthMovesTailBelowContent() throws {
    let h = try disclosure()
    defer { h.shutdown() }
    try key("g", in: h)
    let lines = h.frame.split(whereSeparator: \.isNewline)
    let extra = try #require(lines.firstIndex { $0.contains("growth-last") })
    let tail = try #require(lines.firstIndex { $0.contains("tail") })
    #expect(extra < tail)
    try key("g", in: h)
    #expect(!h.frame.contains("growth-last"))
    #expect(h.frame.contains("tail"))
  }

  @Test func setA088DisclosureStyleSwitchKeepsActionRouting() throws {
    let h = try disclosure()
    defer { h.shutdown() }
    try key("s", in: h)
    try h.clickText("Child action")
    #expect(h.frame.contains("calls=1"))
    #expect(h.frame.contains("leaf-B"))
    try key("s", in: h)
    try h.clickText("Child action")
    #expect(h.frame.contains("calls=2"))
  }

  @Test func setA089DisclosureDisabledChildRebindsOnReenable() throws {
    let h = try disclosure()
    defer { h.shutdown() }
    try key("d", in: h)
    try h.clickText("Child action")
    #expect(h.frame.contains("calls=0"))
    try key("d", in: h)
    try h.clickText("Child action")
    #expect(h.frame.contains("calls=1"))
  }

  @Test func setA090DisclosureWidthRoundTripKeepsSemanticChildren() throws {
    let h = try disclosure()
    defer { h.shutdown() }
    for _ in 0..<2 {
      try key("w", in: h)
      for label in ["leaf-A", "leaf-B", "leaf-C", "nested-leaf", "Child action"] {
        #expect(h.runLoop.latestSemanticSnapshot.accessibilityNodes.contains { $0.label == label })
      }
      try h.clickText("Child action")
    }
    #expect(h.frame.contains("calls=2"))
  }

  @Test func setA091ListReorderMovesByCurrentOrderAndActivatesCurrentID() throws {
    let h = try collection()
    defer { h.shutdown() }
    try navigate(1, in: h)
    try key("r", in: h)
    try h.pressKey(.init(.arrowDown))
    try activate(0, in: h)
  }

  @Test func setA092ListInsertionBeforeFocusDoesNotRetargetAction() throws {
    let h = try collection()
    defer { h.shutdown() }
    try navigate(1, in: h)
    try key("i", in: h)
    try h.pressKey(.init(.arrowDown))
    try activate(2, in: h)
  }

  @Test func setA093ListRemovalNeverActivatesDepartedRow() throws {
    let h = try collection()
    defer { h.shutdown() }
    try navigate(1, in: h)
    try key("d", in: h)
    try h.pressKey(.init(.arrowDown))
    let focus = try #require(h.runLoop.focusTracker.currentFocusIdentity)
    #expect(h.runLoop.latestSemanticSnapshot.focusRegions.contains { $0.identity == focus })
    try h.pressKey(.init(.return))
    #expect(!h.frame.contains("activated=1 "))
    #expect(h.frame.contains("calls=1"))
    #expect(!h.frame.contains("row<1>"))
  }

  @Test func setA094PrecedingRowGrowthRetainsFocusedAction() throws {
    let h = try collection()
    defer { h.shutdown() }
    try navigate(3, in: h)
    try key("g", in: h)
    try activate(3, in: h)
    try key("g", in: h)
    try h.pressKey(.init(.arrowUp))
    try activate(2, in: h, count: 2)
  }

  @Test func setA095WidthChangeCannotRestoreOldListSelection() throws {
    let h = try collection()
    defer { h.shutdown() }
    try navigate(3, in: h)
    try key("w", in: h)
    try activate(3, in: h)
    try key("w", in: h)
    try h.pressKey(.init(.arrowDown))
    try activate(4, in: h, count: 2)
  }

  @Test func setA096EmptyThenRestoredListPublishesLiveActions() throws {
    let h = try collection()
    defer { h.shutdown() }
    try navigate(1, in: h)
    try key("e", in: h)
    #expect(!h.frame.contains("row<"))
    try key("e", in: h)
    try h.focusText("row<0>")
    try activate(0, in: h)
    try h.pressKey(.init(.arrowDown))
    try activate(1, in: h, count: 2)
  }

  @Test func setA097EndHomeRoundTripAfterHeightChangeKeepsSelectionAndFocusTogether() throws {
    let h = try collection()
    defer { h.shutdown() }
    try h.focusText("row<0>")
    try h.pressKey(.init(.end))
    try key("g", in: h)
    try h.pressKey(.init(.home))
    try activate(0, in: h)
    try h.pressKey(.init(.arrowDown))
    try activate(1, in: h, count: 2)
  }

  @Test func setA098EndViewportShrinkCanReverseOneRow() throws {
    let h = try collection()
    defer { h.shutdown() }
    try navigate(5, in: h)
    try h.pressKey(.init(.end))
    try key("h", in: h)
    try h.pressKey(.init(.arrowUp))
    try activate(4, in: h)
  }

  @Test func setA099TableHeaderToggleKeepsFocusedRowSelection() throws {
    let h = try collection(table: true)
    defer { h.shutdown() }
    try navigate(2, in: h)
    let focus = h.runLoop.focusTracker.currentFocusIdentity
    try key("t", in: h)
    #expect(h.runLoop.focusTracker.currentFocusIdentity == focus)
    #expect(h.frame.contains("row<2>"))
    #expect(h.frame.contains("selection=2"))
    try key("t", in: h)
    try h.pressKey(.init(.arrowDown))
    #expect(h.frame.contains("row<3>"))
    #expect(h.frame.contains("selection=3"))
  }

  @Test func setA100TableReorderAndWidthChangeKeepCurrentNavigationOrder() throws {
    let h = try collection(table: true)
    defer { h.shutdown() }
    try navigate(2, in: h)
    try key("r", in: h)
    try key("w", in: h)
    try h.pressKey(.init(.arrowUp))
    #expect(h.frame.contains("row<3>"))
    #expect(h.frame.contains("selection=3"))
  }

  private func disclosure() throws -> StressRuntimeHarness<SetADisclosure> {
    try StressRuntimeHarness(
      rootIdentity: testIdentity("SetADisclosure"), size: .init(width: 44, height: 24)
    ) {
      SetADisclosure()
    }
  }

  private func collection(table: Bool = false) throws -> StressRuntimeHarness<SetACollection> {
    try StressRuntimeHarness(
      rootIdentity: testIdentity("SetACollection"), size: .init(width: 44, height: 18)
    ) {
      SetACollection(table: table)
    }
  }

  private func key<V: View>(_ character: Character, in h: StressRuntimeHarness<V>) throws {
    try h.pressKey(.init(.character(character), modifiers: .ctrl))
  }

  private func activate(
    _ row: Int, in h: StressRuntimeHarness<SetACollection>, count: Int = 1
  ) throws {
    try #require(
      h.frame.contains("row<\(row)>"), "Target must be visible before activation:\n\(h.frame)")
    try h.pressKey(.init(.return))
    do {
      #expect(h.frame.contains("activated=\(row) calls=\(count)"), "\(h.frame)")
      #expect(h.frame.contains("selection=\(row)"), "\(h.frame)")
    }
  }

  private func navigate(_ row: Int, in h: StressRuntimeHarness<SetACollection>) throws {
    try h.focusText("row<0>")
    for _ in 0..<row { try h.pressKey(.init(.arrowDown)) }
    try #require(h.frame.contains("selection=\(row)"), "\(h.frame)")
    try #require(h.frame.contains("row<\(row)>"), "\(h.frame)")
  }
}

@MainActor
private struct SetADisclosure: View {
  @State private var outer = true
  @State private var inner = true
  @State private var reversed = false
  @State private var branch = false
  @State private var empty = false
  @State private var grown = false
  @State private var compact = false
  @State private var disabled = false
  @State private var narrow = false
  @State private var calls = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      DisclosureGroup("Outer", isExpanded: $outer) {
        if !empty {
          ForEach(reversed ? ["C", "B", "A"] : ["A", "B", "C"], id: \.self) { Text("leaf-\($0)") }
        }
        if branch {
          Text("branch-new-1")
          Text("branch-new-2")
        } else {
          Text("branch-old")
        }
        DisclosureGroup("Inner", isExpanded: $inner) { Text("nested-leaf") }
        Button("Child action") { calls += 1 }.disabled(disabled)
        if grown { Text("growth-first\ngrowth-middle\ngrowth-last") }
        Text("tail")
      }
      .disclosureGroupStyle(compact ? AnyDisclosureGroupStyle.compact : .automatic)
      .frame(width: narrow ? 20 : 36, alignment: .leading)
      Text("calls=\(calls)")
    }
    .onKeyPress(.character("o"), modifiers: .ctrl) { _ in
      outer.toggle()
      return .handled
    }
    .onKeyPress(.character("n"), modifiers: .ctrl) { _ in
      inner.toggle()
      return .handled
    }
    .onKeyPress(.character("r"), modifiers: .ctrl) { _ in
      reversed.toggle()
      return .handled
    }
    .onKeyPress(.character("b"), modifiers: .ctrl) { _ in
      branch.toggle()
      return .handled
    }
    .onKeyPress(.character("e"), modifiers: .ctrl) { _ in
      empty.toggle()
      return .handled
    }
    .onKeyPress(.character("g"), modifiers: .ctrl) { _ in
      grown.toggle()
      return .handled
    }
    .onKeyPress(.character("s"), modifiers: .ctrl) { _ in
      compact.toggle()
      return .handled
    }
    .onKeyPress(.character("d"), modifiers: .ctrl) { _ in
      disabled.toggle()
      return .handled
    }
    .onKeyPress(.character("w"), modifiers: .ctrl) { _ in
      narrow.toggle()
      return .handled
    }
  }
}

@MainActor
private struct SetACollection: View {
  let table: Bool
  @State private var rows = Array(0..<6)
  @State private var selection: Int? = 0
  @State private var activated = -1
  @State private var calls = 0
  @State private var grown = false
  @State private var narrow = false
  @State private var short = false
  @State private var headers = true

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if table {
        Table(
          rows, id: \.self, selection: $selection,
          columns: [.init("Rows", width: narrow ? 12 : 28)]
        ) { row in content(row) }
        .tableHeaders(headers ? .visible : .hidden)
        .frame(width: narrow ? 18 : 34, height: short ? 5 : 12)
      } else {
        List(
          rows, id: \.self, selection: $selection,
          onActivate: {
            activated = $0
            calls += 1
          }
        ) { row in content(row) }
        .listStyle(SetAListStyle())
        .scrollIndicators(.hidden)
        .frame(width: narrow ? 12 : 30, height: short ? 4 : 8)
      }
      Text("selection=\(selection ?? -99)")
      Text("activated=\(activated) calls=\(calls)")
    }
    .onKeyPress(.character("r"), modifiers: .ctrl) { _ in
      rows.reverse()
      return .handled
    }
    .onKeyPress(.character("i"), modifiers: .ctrl) { _ in
      rows.insert(-1, at: 0)
      return .handled
    }
    .onKeyPress(.character("d"), modifiers: .ctrl) { _ in
      rows.removeAll { $0 == 1 }
      return .handled
    }
    .onKeyPress(.character("e"), modifiers: .ctrl) { _ in
      rows = rows.isEmpty ? Array(0..<6) : []
      return .handled
    }
    .onKeyPress(.character("g"), modifiers: .ctrl) { _ in
      grown.toggle()
      return .handled
    }
    .onKeyPress(.character("w"), modifiers: .ctrl) { _ in
      narrow.toggle()
      return .handled
    }
    .onKeyPress(.character("h"), modifiers: .ctrl) { _ in
      short.toggle()
      return .handled
    }
    .onKeyPress(.character("t"), modifiers: .ctrl) { _ in
      headers.toggle()
      return .handled
    }
  }

  private func content(_ row: Int) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("row<\(row)>")
      if grown && row == 0 { Text("extra-1\nextra-2\nextra-3\nextra-4") }
    }
  }
}

private struct SetAListStyle: ListStyle, Equatable {
  @MainActor
  func resolvePresentation(for configuration: ListStyleConfiguration) -> ListStylePresentation {
    .init(
      contentInsets: .init(top: 0, leading: 0, bottom: 0, trailing: 0),
      showsRowSeparators: false, showsSectionSeparators: false)
  }
}
