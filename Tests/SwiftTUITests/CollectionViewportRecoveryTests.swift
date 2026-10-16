import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized)
struct CollectionViewportRecoveryTests {
  @Test("multiple-selection table navigation reveals its caret without checking rows")
  func compactMultipleSelection() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("CompactMultipleSelection"), size: CellSize(width: 36, height: 12)
    ) {
      ViewportRecoveryTable(heights: [1, 1, 1, 1], height: 5, separators: false, multiple: true)
    }
    defer { harness.shutdown() }
    let identity = try #require(harness.runLoop.latestSemanticSnapshot.scrollRoutes.first?.identity)
    _ = try harness.focus(identity)
    for _ in 0..<2 { _ = try harness.pressKey(KeyPress(.arrowDown)) }
    #expect(harness.frame.contains("ROW2:0"), "\(harness.frame)")
    #expect(harness.frame.contains("checked=[0]"))
    _ = try harness.pressKey(KeyPress(.return))
    #expect(harness.frame.contains("checked=[0, 2]"))
  }

  @Test("a newer scroll key supersedes the pending table selection reveal")
  func pendingSelectionRevealYieldsToScroll() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("PendingTableReveal"), size: CellSize(width: 36, height: 12)
    ) { ViewportRecoveryTable(heights: [1, 1, 1, 1], height: 5, separators: false) }
    defer { harness.shutdown() }
    let identity = try #require(harness.runLoop.latestSemanticSnapshot.scrollRoutes.first?.identity)
    _ = try harness.focus(identity)
    for key in [KeyEvent.arrowDown, .arrowDown, .home] {
      #expect(harness.runLoop.handleKeyPress(KeyPress(key)) == nil)
    }
    _ = try harness.render()
    #expect(harness.frame.contains("selected=2"))
    #expect(harness.frame.contains("ROW0:0"), "\(harness.frame)")
    #expect(!harness.frame.contains("ROW2:0"), "explicit scrolling owns the window")
  }

  @Test("table growth respects an explicit scroll away from selection", arguments: [false, true])
  func tableGrowthRespectsScroll(simultaneous: Bool) throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("TableGrowthScrollPriority"), size: CellSize(width: 36, height: 16)
    ) { ViewportRecoveryGrowingTable() }
    defer { harness.shutdown() }
    let identity = try #require(harness.runLoop.latestSemanticSnapshot.scrollRoutes.first?.identity)
    _ = try harness.focus(identity)
    for _ in 1...7 { _ = try harness.pressKey(KeyPress(.arrowDown)) }
    try #require(harness.frame.contains("ROW7:0"))
    if simultaneous {
      _ = try harness.pressKey(KeyPress(.character("s"), modifiers: .ctrl))
    } else {
      _ = try harness.pressKey(KeyPress(.home))
      _ = try harness.pressKey(KeyPress(.character("g"), modifiers: .ctrl))
    }
    #expect(harness.frame.contains("selected=7"))
    #expect(harness.frame.contains("ROW0:0"), "\(harness.frame)")
    #expect(!harness.frame.contains("ROW7:0"))
  }

  @Test("removing the focused item does not reveal its positional replacement")
  func removedItemKeepsFallback() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("RemovedViewportRecoveryItem"),
      size: CellSize(width: 36, height: 14)
    ) { ViewportRecoveryGrowingList(countChange: 0, removesFocusedRow: true) }
    defer { harness.shutdown() }
    _ = try harness.focusText("ROW0:0")
    for _ in 1...7 { _ = try harness.pressKey(KeyPress(.arrowDown)) }
    let previousFocus = harness.runLoop.focusTracker.currentFocusIdentity
    _ = try harness.pressKey(KeyPress(.character("g"), modifiers: .ctrl))
    #expect(harness.runLoop.focusTracker.currentFocusIdentity != previousFocus)
    #expect(!harness.frame.contains("ROW7:0"))
    #expect(!harness.frame.contains("ROW8:0"), "the old index is not a recovery target")
    _ = try harness.pressKey(KeyPress(.return))
    #expect(!harness.frame.contains("activated=7"))
    #expect(!harness.frame.contains("activated=8"))
  }

  @Test("table geometry changes preserve the visible active row", arguments: [false, true])
  func tableGrowthKeepsSelectedRowVisible(multiple: Bool) throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ViewportRecoveryTableGrowth"),
      size: CellSize(width: 36, height: 16)
    ) { ViewportRecoveryGrowingTable(multiple: multiple) }
    defer { harness.shutdown() }
    let identity = try #require(harness.runLoop.latestSemanticSnapshot.scrollRoutes.first?.identity)
    _ = try harness.focus(identity)
    for _ in 1...7 { _ = try harness.pressKey(KeyPress(.arrowDown)) }
    try #require(
      harness.runLoop.focusTracker.focusRegions.first { $0.identity == identity }?
        .collectionFocusTarget?.rowIndex == 7)
    try #require(harness.frame.contains("ROW7:0"))
    _ = try harness.pressKey(KeyPress(.character("g"), modifiers: .ctrl))
    #expect(harness.runLoop.focusTracker.currentFocusIdentity == identity)
    #expect(
      harness.runLoop.focusTracker.focusRegions.first { $0.identity == identity }?
        .collectionFocusTarget?.rowIndex == 7)
    #expect(harness.frame.contains(multiple ? "checked=[0]" : "selected=7"))
    #expect(harness.frame.contains("ROW7:0"), "\(harness.frame)")
  }

  @Test(
    "table navigation fits measured rows beside indicators",
    arguments: [3, 4, 5, 6, 7, 8, 9, 10], [false, true])
  func compactNavigation(height: Int, separators: Bool) throws {
    for heights in [[1, 1, 1, 1], [1, 3, 1, 1], [3, 1, 3, 1], [1, 1, 1, 3], [1, 2, 3, 4]] {
      let harness = try StressRuntimeHarness(
        rootIdentity: testIdentity("ViewportRecoveryNavigation"),
        size: CellSize(width: 36, height: 16)
      ) { ViewportRecoveryTable(heights: heights, height: height, separators: separators) }
      defer { harness.shutdown() }
      let identity = try #require(
        harness.runLoop.latestSemanticSnapshot.scrollRoutes.first?.identity)
      _ = try harness.focus(identity)
      for row in Array(1..<4) + Array((0..<3).reversed()) {
        let delta = harness.frame.contains("selected=\(row + 1)") ? KeyEvent.arrowUp : .arrowDown
        _ = try harness.pressKey(KeyPress(delta))
        try #require(harness.frame.contains("selected=\(row)"))
        try #require(
          harness.frame.contains("ROW\(row):0"),
          "height=\(height) separators=\(separators) heights=\(heights) target=\(row)\n\(harness.frame)"
        )
      }
    }
  }

  @Test("list growth preserves focus when membership also changes", arguments: [0, 1, -1])
  func growthWithMembershipChange(countChange: Int) throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ViewportRecoveryGrowthAppend"),
      size: CellSize(width: 36, height: 14)
    ) { ViewportRecoveryGrowingList(countChange: countChange) }
    defer { harness.shutdown() }
    _ = try harness.focusText("ROW0:0")
    for _ in 1...7 { _ = try harness.pressKey(KeyPress(.arrowDown)) }
    let focus = harness.runLoop.focusTracker.currentFocusIdentity
    try #require(harness.frame.contains("ROW7:0"))
    _ = try harness.pressKey(KeyPress(.character("g"), modifiers: .ctrl))
    #expect(harness.frame.contains("ROW7:0"), "\(harness.frame)")
    #expect(harness.runLoop.focusTracker.currentFocusIdentity == focus, "\(harness.frame)")
    _ = try harness.pressKey(KeyPress(.return))
    #expect(harness.frame.contains("activated=7"), "\(harness.frame)")
  }
}

@MainActor
private struct ViewportRecoveryGrowingTable: View {
  var multiple = false
  @State private var grown = false
  var body: some View {
    ScrollViewReader { proxy in
      ViewportRecoveryTable(
        heights: (0..<12).map { grown && $0 == 6 ? 6 : 1 },
        height: 8, separators: true, multiple: multiple
      )
      .scrollIndicators(.hidden)
      .onKeyPress(.character("g"), modifiers: .ctrl) { _ in
        grown.toggle()
        return .handled
      }
      .onKeyPress(.character("s"), modifiers: .ctrl) { _ in
        grown = true
        proxy.scrollTo(0, anchor: .top)
        return .handled
      }
    }
  }
}

@MainActor
private struct ViewportRecoveryTable: View {
  let heights: [Int]
  let height: Int
  let separators: Bool
  var multiple = false
  @State private var selected: Int? = 0
  @State private var checked: Set<Int> = [0]
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      table.tableHeaders(.hidden).frame(height: height)
      Text("selected=\(selected ?? -1) checked=\(checked.sorted())")
    }
  }

  @ViewBuilder
  private var table: some View {
    if multiple {
      Table(selection: $checked, columns: [TableColumn("Value", width: 24)]) { rows }
    } else {
      Table(selection: $selected, columns: [TableColumn("Value", width: 24)]) { rows }
    }
  }

  private var rows: some View {
    ForEach(0..<heights.count, id: \.self) { row in
      TableRow {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(0..<heights[row], id: \.self) { line in Text("ROW\(row):\(line)") }
        }
      }
      .fixedSize(horizontal: false, vertical: true)
      .listRowSeparator(separators ? .visible : .hidden)
      .tag(row)
      .id(row)
    }
  }
}

@MainActor
private struct ViewportRecoveryGrowingList: View {
  let countChange: Int
  var removesFocusedRow = false
  @State private var grown = false
  @State private var selected: Int? = 0
  @State private var activated = -1
  private var rows: [Int] {
    Array(0..<(grown ? 12 + countChange : 12)).filter {
      !(grown && removesFocusedRow && $0 == 7)
    }
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      List(
        rows, id: \.self, selection: $selected,
        onActivate: { activated = $0 }
      ) { row in
        VStack(alignment: .leading, spacing: 0) {
          ForEach(0..<(grown && row == 6 ? 6 : 1), id: \.self) { line in
            Text("ROW\(row):\(line)")
          }
        }
      }.listStyle(ViewportRecoveryListStyle()).scrollIndicators(.hidden).frame(height: 6)
      Text("selected=\(selected ?? -1) activated=\(activated)")
    }.onKeyPress(.character("g"), modifiers: .ctrl) { _ in
      grown.toggle()
      return .handled
    }
  }
}

private struct ViewportRecoveryListStyle: ListStyle {
  @MainActor
  func resolvePresentation(for configuration: ListStyleConfiguration) -> ListStylePresentation {
    ListStylePresentation(
      contentInsets: .init(top: 0, leading: 0, bottom: 0, trailing: 0),
      showsRowSeparators: false, showsSectionSeparators: false)
  }
}
