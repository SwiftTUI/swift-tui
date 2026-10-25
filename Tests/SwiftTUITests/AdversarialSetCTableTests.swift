@_spi(Testing) import SwiftTUITestSupport
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized)
struct AdversarialSetCTableTests {
  @Test func setC122FixedWidthHeaderStaysInBudget() throws {
    let lines = SetCTable.lines(
      Table(columns: [TableColumn("Service", width: 3), TableColumn("Status")]) {
        TableRow {
          Text("api")
          Text("ok")
        }
      }, name: "setC122", width: 30)
    #expect(SetCTable.widths(lines).count == 1, "\(lines)")
    let joined = lines.joined(separator: "\n")
    #expect(!joined.contains("Service"), "\(lines)")
    #expect(joined.contains("Se…"), "\(lines)")
  }

  @Test func setC123WideGraphemeStaysInColumnBudget() throws {
    let lines = SetCTable.lines(
      Table(columns: [TableColumn("K", width: 3), TableColumn("V")]) {
        TableRow {
          Text("漢字x")
          Text("one")
        }
        TableRow {
          Text("ab")
          Text("two")
        }
      }, name: "setC123", width: 30)
    let joins = SetCTable.joinColumns(lines)
    #expect(joins.count >= 5, "\(lines)")
    #expect(Set(joins.map(\.description)).count == 1, "joins must align: \(lines)")
    #expect(SetCTable.widths(lines).count == 1, "\(lines)")
    #expect(lines.joined(separator: "\n").contains("漢…"), "\(lines)")
  }

  @Test func setC124HiddenSeparatorOnStaticRow() throws {
    let texts = ["one", "two", "three"]
    let plain = SetCTable.contentRows(
      SetCTable.lines(SetCTable.staticTable(.none), name: "setC124-plain"), texts)
    let hiddenRow = SetCTable.lines(SetCTable.staticTable(.row), name: "setC124-row")
    let hiddenCell = SetCTable.lines(SetCTable.staticTable(.cell), name: "setC124-cell")
    let rowIndices = SetCTable.contentRows(hiddenRow, texts)
    let cellIndices = SetCTable.contentRows(hiddenCell, texts)
    try #require(plain.count == 3 && rowIndices.count == 3 && cellIndices.count == 3)
    #expect(plain[1] - plain[0] == 2 && plain[2] - plain[1] == 2)
    #expect(rowIndices[1] - rowIndices[0] == 1, "row-level hidden separator: \(hiddenRow)")
    #expect(rowIndices[2] - rowIndices[1] == 2, "\(hiddenRow)")
    #expect(cellIndices[1] - cellIndices[0] == 1, "cell-level hidden separator: \(hiddenCell)")
    #expect(cellIndices[2] - cellIndices[1] == 2, "\(hiddenCell)")
  }

  @Test func setC125HiddenSeparatorsInDataDrivenTable() throws {
    let rows = ["alpha", "beta", "gamma", "delta"]
    let plain = SetCTable.contentRows(
      SetCTable.lines(
        Table(rows, id: \.self, columns: [TableColumn("Name")]) { row in Text(row) },
        name: "setC125-plain", width: 20, height: 16), rows)
    let hidden = SetCTable.lines(
      Table(rows, id: \.self, columns: [TableColumn("Name")]) { row in
        Text(row).listRowSeparator(.hidden)
      }, name: "setC125-hidden", width: 20, height: 16)
    let hiddenRows = SetCTable.contentRows(hidden, rows)
    try #require(plain.count == 4 && hiddenRows.count == 4, "\(hidden)")
    #expect(plain[1] - plain[0] == 2)
    // STUI-1209 (fixed in wave 2): data-driven rows honor listRowSeparator(.hidden)
    // like static rows (setC124).
    #expect(hiddenRows[1] - hiddenRows[0] == 1, "\(hidden)")
    #expect(hiddenRows[3] - hiddenRows[0] == 3, "\(hidden)")
  }

  @Test func setC126TitleAlignmentDefaultsToCellAlignment() throws {
    let lines = SetCTable.lines(
      Table(columns: [
        TableColumn("N", width: 6, alignment: .trailing),
        TableColumn("C", width: 7, alignment: .trailing, titleAlignment: .center),
      ]) {
        TableRow {
          Text("1")
          Text("2")
        }
      }, name: "setC126", width: 30)
    let header = try #require(lines.first { $0.contains("N") && $0.contains("C") }, "\(lines)")
    let body = try #require(lines.first { $0.contains("1") && $0.contains("2") }, "\(lines)")
    let n = try #require(Array(header).firstIndex(of: "N"))
    let c = try #require(Array(header).firstIndex(of: "C"))
    let one = try #require(Array(body).firstIndex(of: "1"))
    let two = try #require(Array(body).firstIndex(of: "2"))
    #expect(n == one, "a trailing title aligns with trailing cells: \(header) / \(body)")
    #expect(two - c == 3, "a centered 1-cell title in a 7-cell column sits 3 cells in: \(header)")
  }

  @Test func setC127SurplusCellsOmittedMissingBlank() throws {
    let lines = SetCTable.lines(
      Table(columns: [TableColumn("A", width: 4), TableColumn("B", width: 4)]) {
        TableRow {
          Text("one")
          Text("two")
          Text("surplus")
        }
        TableRow {
          Text("solo")
        }
      }, name: "setC127", width: 30)
    let joined = lines.joined(separator: "\n")
    #expect(!joined.contains("surp"), "\(lines)")
    let solo = try #require(lines.first { $0.contains("solo") }, "\(lines)")
    let cells = SetCTable.cells(solo)
    try #require(cells.count == 2, "\(solo)")
    #expect(cells[1].isEmpty, "\(solo)")
    #expect(SetCTable.widths(lines).count == 1, "\(lines)")
  }

  @Test func setC128ColumnWidthHighWaterMarkHolds() throws {
    var rows = (0..<30).map { SetCTableRow(id: "r\($0)") }
    rows[20] = SetCTableRow(id: "wide-value-20x")
    let box = SetCTableBox()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC128"),
      size: .init(width: 30, height: 6)
    ) {
      Table(rows, selection: box.selection, columns: [TableColumn("Name")]) { row in
        Text(row.id)
      }
    }
    defer { h.shutdown() }
    let narrow = SetCTable.widths(h.frame.split(separator: "\n").map(String.init)).max() ?? 0
    _ = try h.pressKey(.init(.tab))
    for _ in 0..<21 { _ = try h.pressKey(.init(.arrowDown)) }
    try #require(h.frame.contains("wide-value-20x"), "\(h.frame)")
    let wide = SetCTable.widths(h.frame.split(separator: "\n").map(String.init)).max() ?? 0
    try #require(wide > narrow, "the wide row must widen the column: \(narrow) -> \(wide)")
    for _ in 0..<21 { _ = try h.pressKey(.init(.arrowUp)) }
    try #require(h.frame.contains("r0"), "\(h.frame)")
    let back = SetCTable.widths(h.frame.split(separator: "\n").map(String.init)).max() ?? 0
    #expect(back == wide, "\(h.frame)")
  }

  // Wave 2 (STUI-1164) neighbors of the STUI-1209 repair.
  @Test func wave2a27DataTableMatchesStaticSeparators() throws {
    let rows = ["alpha", "beta", "gamma", "delta"]
    let data = SetCTable.lines(
      Table(rows, id: \.self, columns: [TableColumn("Name")]) { row in
        if row == "beta" {
          Text(row).listRowSeparator(.hidden)
        } else {
          Text(row)
        }
      }, name: "wave2a27-data", width: 20, height: 16)
    let authored = SetCTable.lines(
      Table(columns: [TableColumn("Name")]) {
        TableRow { Text("alpha") }
        TableRow { Text("beta").listRowSeparator(.hidden) }
        TableRow { Text("gamma") }
        TableRow { Text("delta") }
      }, name: "wave2a27-static", width: 20, height: 16)
    let indices = SetCTable.contentRows(data, rows)
    try #require(indices.count == 4, "\(data)")
    #expect(zip(indices.dropFirst(), indices).map { $0 - $1 } == [1, 1, 2], "\(data)")
    #expect(
      data.map(SetCTable.trimmed).filter { !$0.isEmpty }
        == authored.map(SetCTable.trimmed).filter { !$0.isEmpty },
      "data \(data) vs static \(authored)")
  }

  @Test func wave2a28ScrolledDataTableHonorsHiddenSeparators() throws {
    let rows = (0..<8).map { SetCTableRow(id: "r\($0)") }
    let names = rows.map(\.id)
    let box = SetCTableBox()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("wave2a28"),
      size: .init(width: 20, height: 9)
    ) {
      Table(rows, selection: box.selection, columns: [TableColumn("Name")]) { row in
        Text(row.id).listRowSeparator(.hidden)
      }.scrollIndicators(.hidden)
    }
    defer { h.shutdown() }
    func visible() -> [Int] {
      SetCTable.contentRows(h.frame.split(separator: "\n").map(String.init), names)
    }
    let top = visible()
    #expect(top.count == 5, "\(h.frame)")
    #expect(zip(top.dropFirst(), top).allSatisfy { $0 - $1 == 1 }, "\(h.frame)")
    _ = try h.pressKey(.init(.tab))
    _ = try h.pressKey(.init(.end))
    let bottom = visible()
    #expect(h.frame.contains("r7"), "\(h.frame)")
    #expect(bottom.count == 5, "\(h.frame)")
    #expect(zip(bottom.dropFirst(), bottom).allSatisfy { $0 - $1 == 1 }, "\(h.frame)")
  }

  @Test func wave2a29ScrollHostedDataTableHonorsHiddenSeparators() throws {
    // Equal-width ids keep the high-water column width out of the oracle.
    let rows = (0..<30).map { SetCTableRow(id: $0 < 10 ? "row0\($0)" : "row\($0)") }
    let names = rows.map(\.id)
    let box = SetCTableBox()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("wave2a29"),
      size: .init(width: 24, height: 10)
    ) {
      ScrollView {
        Table(rows, selection: box.selection, columns: [TableColumn("Name")]) { row in
          Text(row.id).listRowSeparator(.hidden)
        }
      }.scrollIndicators(.hidden)
    }
    defer { h.shutdown() }
    func visible() -> [Int] {
      SetCTable.contentRows(h.frame.split(separator: "\n").map(String.init), names)
    }
    let top = visible()
    #expect(top.count >= 6, "\(h.frame)")
    #expect(zip(top.dropFirst(), top).allSatisfy { $0 - $1 == 1 }, "\(h.frame)")
    let point = try #require(h.point(forText: "row01"))
    for _ in 0..<12 { _ = try h.scrollPointer(at: point, deltaY: 1) }
    let middle = visible()
    #expect(middle.count >= 9, "\(h.frame)")
    #expect(zip(middle.dropFirst(), middle).allSatisfy { $0 - $1 == 1 }, "\(h.frame)")
    #expect(h.frame.contains("row12"), "\(h.frame)")
  }

  // Wave 3 (STUI-1230): source-backed automatic columns keep a monotonic
  // high-water width as rows are realized, in every hosting shape
  // (Collections.md:135-138, Divergences-And-Gaps.md:455-458).
  @Test(arguments: [SetCTableHosting.scrollView, .unhosted, .scrollViewStack])
  func wave3b01LaterWideRowWidensItsColumn(hosting: SetCTableHosting) throws {
    let h = try SetCTable.wideRowHarness("wave3b01-\(hosting)", hosting: hosting)
    defer { h.shutdown() }
    #expect(!h.frame.contains("row20"), "\(h.frame)")
    try #require(try SetCTable.wheel(h, until: { $0.contains("row21") }), "\(h.frame)")
    #expect(h.frame.contains("row20x"), "\(hosting): \(h.frame)")
    #expect(!h.frame.contains("row2…"), "\(hosting): \(h.frame)")
    #expect(SetCTable.tableWidths(h.frame).count == 1, "\(hosting): \(h.frame)")
    let rerendered = try h.render()
    #expect(rerendered.contains("row20x"), "\(hosting) after re-render: \(rerendered)")
  }

  @Test func wave3b02NarrowerLaterRowsNeverShrinkAColumn() throws {
    var rows = (0..<30).map { SetCTableRow(id: $0 < 10 ? "row0\($0)" : "row\($0)") }
    rows[0] = SetCTableRow(id: "row00-wide")
    let h = try SetCTable.harness("wave3b02", rows: rows, hosting: .scrollView)
    defer { h.shutdown() }
    let initial = SetCTable.tableWidths(h.frame)
    try #require(initial.count == 1 && h.frame.contains("row00-wide"), "\(h.frame)")
    try #require(try SetCTable.wheel(h, until: { $0.contains("row24") }), "\(h.frame)")
    #expect(!h.frame.contains("row00"), "\(h.frame)")
    #expect(SetCTable.tableWidths(h.frame) == initial, "\(h.frame)")
    try #require(
      try SetCTable.wheel(h, deltaY: -1, until: { $0.contains("row00") }), "\(h.frame)")
    #expect(SetCTable.tableWidths(h.frame) == initial, "\(h.frame)")
  }

  @Test func wave3b03FixedColumnWidthIgnoresLaterWideRow() throws {
    var rows = (0..<30).map { SetCTableRow(id: $0 < 10 ? "row0\($0)" : "row\($0)") }
    rows[20] = SetCTableRow(id: "row20x")
    let h = try SetCTable.harness(
      "wave3b03", rows: rows, hosting: .scrollView, column: TableColumn("Name", width: 5))
    defer { h.shutdown() }
    let initial = SetCTable.tableWidths(h.frame)
    try #require(try SetCTable.wheel(h, until: { $0.contains("row21") }), "\(h.frame)")
    #expect(h.frame.contains("row2…") && !h.frame.contains("row20x"), "\(h.frame)")
    #expect(SetCTable.tableWidths(h.frame) == initial, "\(h.frame)")
  }

  @Test func wave3b04WideRowAndHiddenSeparatorsAgree() throws {
    var rows = (0..<30).map { SetCTableRow(id: $0 < 10 ? "row0\($0)" : "row\($0)") }
    rows[20] = SetCTableRow(id: "row20x")
    let h = try SetCTable.harness(
      "wave3b04", rows: rows, hosting: .scrollView, hidesSeparators: true)
    defer { h.shutdown() }
    try #require(try SetCTable.wheel(h, until: { $0.contains("row22") }), "\(h.frame)")
    let visible = SetCTable.contentRows(
      h.frame.split(separator: "\n").map(String.init), rows.map(\.id))
    #expect(visible.count >= 6, "\(h.frame)")
    #expect(zip(visible.dropFirst(), visible).allSatisfy { $0 - $1 == 1 }, "\(h.frame)")
    #expect(h.frame.contains("row20x"), "\(h.frame)")
  }

  // Wave 3 (FW3-E, STUI-1239): a data-driven table's interaction band counts
  // the rows its window shows by each row's real line span. A row whose
  // separator is hidden takes one line, so a band sized at visible lines / 2
  // left the lower visible rows without a pointer route or row action
  // (Collections.md:39-43, StyleModifiers.swift:1616-1622).
  @Test(arguments: SetCBandSeparators.allCases)
  func wave3e01LowestVisibleRowSelectsAtEveryRowSpan(_ separators: SetCBandSeparators) throws {
    let box = SetCTableBox()
    box.selected = "r100"
    let h = try SetCTable.bandHarness(
      "wave3e01-\(separators)", box: box, separators: separators, height: 120)
    defer { h.shutdown() }
    let visible = SetCTable.bandRows(h.frame)
    try #require(visible.count >= 40 && visible.first != "r000", "\(h.frame)")
    let target = visible[visible.count - 1]
    _ = try h.clickText(target)
    #expect(
      box.selected == target, "\(separators): clicked \(target); visible \(visible[0])…\(target)")
  }

  // The band of the frame after End covers the window that frame places,
  // although its rows were not measured when the band was sized. `paged`
  // reaches End from a window two pages down from the top.
  @Test(arguments: [false, true])
  func wave3e02LastRowSelectsAfterEndInHiddenSeparatorTable(paged: Bool) throws {
    let box = SetCTableBox()
    box.selected = "r100"
    let h = try SetCTable.bandHarness(
      "wave3e02-\(paged)", box: box, separators: .hidden, height: 64)
    defer { h.shutdown() }
    _ = try h.pressKey(.init(.tab))
    if paged {
      for key in [KeyEvent.home, .pageDown, .pageDown] { _ = try h.pressKey(.init(key)) }
    }
    _ = try h.pressKey(.init(.end))
    let visible = SetCTable.bandRows(h.frame)
    try #require(visible.last == "r199" && visible.count >= 40, "\(h.frame)")
    _ = try h.clickText("r199")
    #expect(box.selected == "r199", "visible \(visible[0])…r199")
  }

  // Paging into rows no frame has measured yet: the page's lowest row selects.
  @Test func wave3e03LowestRowSelectsAfterPagingIntoUnmeasuredRows() throws {
    let box = SetCTableBox()
    box.selected = "r000"
    let h = try SetCTable.bandHarness("wave3e03", box: box, separators: .hidden, height: 64)
    defer { h.shutdown() }
    _ = try h.pressKey(.init(.tab))
    _ = try h.pressKey(.init(.pageDown))
    let visible = SetCTable.bandRows(h.frame)
    try #require(visible.count >= 40 && visible.first != "r000", "\(h.frame)")
    let target = visible[visible.count - 1]
    _ = try h.clickText(target)
    #expect(box.selected == target, "clicked \(target); visible \(visible[0])…\(target)")
  }

  // The assistive review page moves by the rows the window shows, less one
  // row of overlap, as the keyboard page does (w2fa005).
  @Test(arguments: SetCBandSeparators.allCases)
  func wave3e04ReviewPageMovesByTheVisibleRows(_ separators: SetCBandSeparators) throws {
    let box = SetCTableBox()
    box.selected = "r000"
    let h = try SetCTable.bandHarness(
      "wave3e04-\(separators)", box: box, separators: separators, height: 24)
    defer { h.shutdown() }
    let visible = SetCTable.bandRows(h.frame)
    try #require(visible.first == "r000" && visible.count >= 8, "\(h.frame)")
    func review() throws -> AccessibilityNode {
      try #require(
        h.runLoop.publishedAccessibilitySnapshot.accessibilityNodes.first {
          $0.label == "Review items"
        })
    }
    let target = try #require(try review().actionTarget)
    #expect(
      h.runLoop.handleAccessibilityAction(.init(target: target, action: .custom("Next page")))
        == .accepted)
    _ = try h.render()
    #expect(
      try review().control?.value == .number(Double(visible.count)),
      "\(separators): \(visible.count) visible rows")
  }

  @Test func setC129NoColumnsRendersNothing() {
    let lines = SetCTable.lines(
      Table(columns: []) {
        TableRow { Text("hidden") }
      }, name: "setC129", width: 20)
    #expect(SetCTable.widths(lines).isEmpty, "\(lines)")
  }
}

private struct SetCTableRow: Identifiable, Hashable, Sendable {
  var id: String
}

@MainActor
private final class SetCTableBox {
  var selected: String?
  var selection: Binding<String?> {
    .init(get: { self.selected }, set: { self.selected = $0 })
  }
}

/// Row separators of the FW3-E band fixtures: drawn, hidden on every row, or
/// hidden below every other row (mixed per-row `listRowSeparator`).
enum SetCBandSeparators: String, CaseIterable, Sendable, CustomStringConvertible {
  case drawn, hidden, alternating
  var description: String { rawValue }
}

private struct SetCBandTable: View {
  let rows: [SetCTableRow]
  let selection: Binding<String?>
  let separators: SetCBandSeparators

  var body: some View {
    Table(rows, selection: selection, columns: [TableColumn("Name")]) { row in
      switch separators {
      case .drawn:
        Text(row.id)
      case .hidden:
        Text(row.id).listRowSeparator(.hidden)
      case .alternating:
        if row.id.last.flatMap(\.wholeNumberValue).map({ $0.isMultiple(of: 2) }) == true {
          Text(row.id).listRowSeparator(.hidden, edges: .bottom)
        } else {
          Text(row.id)
        }
      }
    }.tableHeaders(.hidden).scrollIndicators(.hidden)
  }
}

private enum SetCSeparatorHiding {
  case none, row, cell
}

enum SetCTableHosting: Sendable, CustomStringConvertible {
  case unhosted, scrollView, scrollViewStack
  var description: String {
    switch self {
    case .unhosted: "unhosted"
    case .scrollView: "scrollView"
    case .scrollViewStack: "scrollViewStack"
    }
  }
}

private struct SetCTableHost: View {
  let rows: [SetCTableRow]
  let selection: Binding<String?>
  let column: TableColumn
  let hosting: SetCTableHosting
  let hidesSeparators: Bool

  var body: some View {
    switch hosting {
    case .unhosted:
      table.scrollIndicators(.hidden)
    case .scrollView:
      ScrollView { table }.scrollIndicators(.hidden)
    case .scrollViewStack:
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          Text("Header")
          table
        }
      }.scrollIndicators(.hidden)
    }
  }

  private var table: some View {
    Table(rows, selection: selection, columns: [column]) { row in
      if hidesSeparators {
        Text(row.id).listRowSeparator(.hidden)
      } else {
        Text(row.id)
      }
    }
  }
}

@MainActor
private enum SetCTable {
  static func lines<V: View>(_ view: V, name: String, width: Int = 24, height: Int = 12)
    -> [String]
  {
    DefaultRenderer().render(
      view, context: .init(identity: testIdentity("SetCTable", name)),
      proposal: .init(width: width, height: height)
    ).rasterSurface.lines
  }

  /// Thirty five-character rows with one six-character row at index 20.
  static func wideRowHarness(_ name: String, hosting: SetCTableHosting) throws
    -> StressRuntimeHarness<SetCTableHost>
  {
    var rows = (0..<30).map { SetCTableRow(id: $0 < 10 ? "row0\($0)" : "row\($0)") }
    rows[20] = SetCTableRow(id: "row20x")
    return try harness(name, rows: rows, hosting: hosting)
  }

  static func harness(
    _ name: String,
    rows: [SetCTableRow],
    hosting: SetCTableHosting,
    column: TableColumn = TableColumn("Name"),
    hidesSeparators: Bool = false
  ) throws -> StressRuntimeHarness<SetCTableHost> {
    let box = SetCTableBox()
    return try StressRuntimeHarness(
      rootIdentity: testIdentity(name),
      size: .init(width: 24, height: 10)
    ) {
      SetCTableHost(
        rows: rows, selection: box.selection, column: column, hosting: hosting,
        hidesSeparators: hidesSeparators)
    }
  }

  /// Two hundred rows `r000`…`r199` at 30 columns.
  static func bandHarness(
    _ name: String, box: SetCTableBox, separators: SetCBandSeparators, height: Int
  ) throws -> StressRuntimeHarness<SetCBandTable> {
    let rows = (0..<200).map { (index: Int) -> SetCTableRow in
      let digits = String(index)
      let padding = String(repeating: "0", count: 3 - digits.count)
      return SetCTableRow(id: "r\(padding)\(digits)")
    }
    return try StressRuntimeHarness(
      rootIdentity: testIdentity(name),
      size: .init(width: 30, height: height)
    ) {
      SetCBandTable(rows: rows, selection: box.selection, separators: separators)
    }
  }

  /// The band fixture's row ids in frame order.
  static func bandRows(_ frame: String) -> [String] {
    var ids: [String] = []
    for line in frame.split(separator: "\n") {
      let tokens = line.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
      if let token = tokens.first(where: isBandRowID) { ids.append(String(token)) }
    }
    return ids
  }

  private static func isBandRowID(_ token: Substring) -> Bool {
    token.count == 4 && token.first == "r" && token.dropFirst().allSatisfy(\.isNumber)
  }

  /// Scrolls one wheel notch at a time over the table body (cell 2, 5 lies
  /// inside the table in every hosting shape) until `done` holds for the
  /// frame; `false` when it never does within `limit` notches.
  static func wheel<Content: View>(
    _ h: StressRuntimeHarness<Content>, deltaY: Int = 1, limit: Int = 48,
    until done: (String) -> Bool
  ) throws -> Bool {
    let point = Point(x: 2, y: 5)
    for _ in 0..<limit {
      if done(h.frame) { return true }
      _ = try h.scrollPointer(at: point, deltaY: deltaY)
    }
    return done(h.frame)
  }

  /// Distinct widths of the table's own lines (those carrying a vertical rule).
  static func tableWidths(_ frame: String) -> Set<Int> {
    widths(frame.split(separator: "\n").map(String.init).filter { $0.contains("│") })
  }

  @ViewBuilder
  static func staticTable(_ hiding: SetCSeparatorHiding) -> some View {
    Table(columns: [TableColumn("Name", width: 6)]) {
      switch hiding {
      case .none:
        TableRow { Text("one") }
      case .row:
        TableRow { Text("one") }.listRowSeparator(.hidden)
      case .cell:
        TableRow { Text("one").listRowSeparator(.hidden) }
      }
      TableRow { Text("two") }
      TableRow { Text("three") }
    }
  }

  /// Distinct cell widths of the non-blank lines (wide glyphs count two).
  static func widths(_ lines: [String]) -> Set<Int> {
    Set(
      lines.map { trimmed($0) }.filter { !$0.isEmpty }.map {
        layoutText(for: $0, width: nil).size.width
      })
  }

  /// Cell columns of vertical rules and joins per non-blank line (wide
  /// glyphs before a join count two cells).
  static func joinColumns(_ lines: [String]) -> [[Int]] {
    lines.map { trimmed($0) }.filter { !$0.isEmpty }.map { line in
      line.indices.compactMap { index in
        guard "│┼┬┴├┤╭╮╰╯".contains(line[index]) else { return nil }
        return layoutText(for: String(line[..<index]), width: nil).size.width
      }
    }
  }

  /// Cell texts between vertical rules, trimmed of their padding.
  static func cells(_ line: String) -> [String] {
    let inner = trimmed(line).split(separator: "│", omittingEmptySubsequences: false)
    return inner.dropFirst().dropLast().map { trimmed(String($0)) }
  }

  /// Indices of lines carrying one of the given cell texts.
  static func contentRows(_ lines: [String], _ texts: [String]) -> [Int] {
    lines.enumerated().compactMap { index, line in
      texts.contains { line.contains($0) } ? index : nil
    }
  }

  static func trimmed(_ line: String) -> String {
    var result = Substring(line)
    while result.first == " " { result.removeFirst() }
    while result.last == " " { result.removeLast() }
    return String(result)
  }
}
