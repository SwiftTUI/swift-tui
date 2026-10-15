import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized)
struct TableFocusUpdateTests {
  @Test("fresh hosted Table rows use their full measured heights", arguments: [false, true])
  func freshTallRows(indexed: Bool) throws {
    let artifacts = DefaultRenderer().render(
      FreshTallTable(indexed: indexed),
      context: ResolveContext(identity: testIdentity("FreshTallTable", "\(indexed)")),
      proposal: ProposedSize(width: 36, height: 12))
    var pending = [artifacts.placedTree]
    var placedTable: PlacedNode?
    while let node = pending.popLast() {
      if node.semanticMetadata.hostedCollectionContainer?.kind == .table {
        placedTable = node
        break
      }
      pending.append(contentsOf: node.children)
    }
    let table = try #require(placedTable)
    let firstRow = try #require(
      table.children.first {
        $0.semanticMetadata.hostedCollectionItem?.role == .tableRow(rowIndex: 0)
      })
    let secondRow = try #require(
      table.children.first {
        $0.semanticMetadata.hostedCollectionItem?.role == .tableRow(rowIndex: 1)
      })
    #expect(firstRow.bounds.size.height == 4)
    #expect(secondRow.bounds.origin.y == firstRow.bounds.origin.y + 5)
    let painted = artifacts.rasterSurface.lines
    for line in 0..<4 {
      let y = firstRow.bounds.origin.y + line
      try #require(painted.indices.contains(y))
      #expect(painted[y].contains("Fresh0:\(line)"), "\(painted.joined(separator: "\n"))")
    }
    try #require(painted.indices.contains(secondRow.bounds.origin.y))
    #expect(painted[secondRow.bounds.origin.y].contains("Fresh1:0"))
  }

  @Test(
    "eager Table windows fit indicators, measured rows, and optional separators",
    arguments: [
      (height: 6, rowLines: 1, separators: true, headers: false),
      (height: 4, rowLines: 1, separators: true, headers: false),
      (height: 8, rowLines: 3, separators: true, headers: false),
      (height: 6, rowLines: 3, separators: true, headers: false),
      (height: 6, rowLines: 10, separators: true, headers: false),
      (height: 8, rowLines: 3, separators: false, headers: false),
      (height: 8, rowLines: 1, separators: true, headers: true),
      (height: 6, rowLines: 1, separators: true, headers: true),
    ])
  func eagerMeasuredWindows(
    geometry: (height: Int, rowLines: Int, separators: Bool, headers: Bool)
  ) throws {
    let artifacts = DefaultRenderer().render(
      EagerMeasuredWindowTable(
        rowLines: geometry.rowLines, separators: geometry.separators, headers: geometry.headers
      ).frame(height: geometry.height),
      context: ResolveContext(identity: testIdentity("EagerMeasuredWindow")),
      proposal: ProposedSize(width: 36, height: 16))
    var pending = [artifacts.placedTree]
    var placedTable: PlacedNode?
    while let node = pending.popLast() {
      if node.semanticMetadata.hostedCollectionContainer?.kind == .table {
        placedTable = node
        break
      }
      pending.append(contentsOf: node.children)
    }
    let table = try #require(placedTable)
    let layout = try #require(table.hostedTableVisibleLayout)
    let navigation = try #require(layout.scrollMetadata?.navigation)
    #expect(navigation.geometry.lineRange(forRow: 1).count == geometry.rowLines)
    #expect(navigation.geometry.line(forRow: 1) == (geometry.separators ? 2 : 1))
    let selected = try #require(layout.lines.first { $0.rowIndex == 1 })
    let painted = artifacts.rasterSurface.lines
    let first = table.bounds.origin.y + selected.yOffset
    try #require(painted.indices.contains(first))
    #expect(painted[first].contains("Window1:0"), "\(painted.joined(separator: "\n"))")
    let bodyCapacity = geometry.height - (geometry.headers ? 4 : 2)
    if geometry.rowLines <= bodyCapacity {
      for line in 0..<geometry.rowLines {
        try #require(painted.indices.contains(first + line))
        #expect(painted[first + line].contains("Window1:\(line)"))
      }
      let bottom = try #require(layout.lines.first { $0.role == .bottomBorder })
      #expect(bottom.yOffset == geometry.height - 1)
      #expect(layout.lines.allSatisfy { $0.yOffset + $0.height <= geometry.height })
    } else {
      #expect(!painted.contains { $0.contains("Window1:\(geometry.rowLines - 1)") })
    }
  }

  @Test(
    "hidden Table changes refresh forward and reverse navigation without changing selection",
    arguments: [false, true], [false, true])
  func hiddenRowsUpdate(indexed: Bool, multiple: Bool) throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("HiddenTableUpdates", "\(indexed)-\(multiple)"),
      size: CellSize(width: 36, height: 16)
    ) {
      UpdatingTable(indexed: indexed, multiple: multiple)
    }
    defer { harness.shutdown() }
    let tableIdentity = try #require(
      harness.runLoop.latestSemanticSnapshot.scrollRoutes.first?.identity)
    _ = try harness.focus(tableIdentity)

    func requireRow(_ row: Int, phase: Int, lines: Int) throws {
      #expect(harness.runLoop.focusTracker.currentFocusIdentity == tableIdentity)
      let version = row == 5 || row == 6 ? phase : 0
      let painted = harness.frame.split(
        omittingEmptySubsequences: false, whereSeparator: \.isNewline)
      let first = try #require(
        painted.firstIndex { $0.contains("R\(row)v\(version):0") }, "\(harness.frame)")
      for line in 0..<lines {
        try #require(painted.indices.contains(first + line), "\(harness.frame)")
        #expect(painted[first + line].contains("R\(row)v\(version):\(line)"), "\(harness.frame)")
      }
      if phase == 2, row == 5 || row == 6 {
        #expect(!harness.frame.contains("R\(row)v1:"), "\(harness.frame)")
        #expect(!harness.frame.contains("R\(row)v2:1"), "\(harness.frame)")
      }
      if multiple {
        #expect(harness.frame.contains("members=[]"), "\(harness.frame)")
        _ = try harness.pressKey(KeyPress(.return))
        #expect(harness.frame.contains("members=[\(row)]"), "\(harness.frame)")
        _ = try harness.pressKey(KeyPress(.space))
        #expect(harness.frame.contains("members=[]"), "\(harness.frame)")
      } else {
        #expect(harness.frame.contains("selected=\(row)"), "\(harness.frame)")
      }
    }

    // Measure the original target, then move its cells outside the viewport.
    for row in 1...6 {
      _ = try harness.pressKey(KeyPress(.arrowDown))
      try requireRow(row, phase: 0, lines: 1)
    }
    for row in (0..<6).reversed() {
      _ = try harness.pressKey(KeyPress(.arrowUp))
      try requireRow(row, phase: 0, lines: 1)
    }
    #expect(!harness.frame.contains("R5v0:"))
    #expect(!harness.frame.contains("R6v0:"))
    _ = try harness.pressKey(KeyPress(.character("g"), modifiers: .ctrl))
    #expect(!harness.frame.contains("R6v1:"))
    try requireRow(0, phase: 1, lines: 1)

    for row in 1...6 {
      _ = try harness.pressKey(KeyPress(.arrowDown))
      let lines: Int
      switch row {
      case 5: lines = 4
      case 6: lines = 3
      default: lines = 1
      }
      try requireRow(row, phase: 1, lines: lines)
    }
    #expect(!harness.frame.contains("R6v0:"))
    for row in 7..<12 {
      _ = try harness.pressKey(KeyPress(.arrowDown))
      try requireRow(row, phase: 1, lines: 1)
    }

    // Shrink both hidden rows and the viewport while the cursor is at the end.
    #expect(!harness.frame.contains("R5v1:"))
    #expect(!harness.frame.contains("R6v1:"))
    _ = try harness.pressKey(KeyPress(.character("g"), modifiers: .ctrl))
    _ = try harness.pressKey(KeyPress(.character("v"), modifiers: .ctrl))
    #expect(harness.runLoop.focusTracker.currentFocusIdentity == tableIdentity)
    if multiple {
      #expect(harness.frame.contains("members=[]"))
    } else {
      #expect(harness.frame.contains("selected=11"))
    }
    for row in (0..<11).reversed() {
      _ = try harness.pressKey(KeyPress(.arrowUp))
      try requireRow(row, phase: 2, lines: 1)
    }
    #expect(!harness.frame.contains("R6v1:"))
    _ = try harness.pressKey(KeyPress(.character("v"), modifiers: .ctrl))
    try requireRow(0, phase: 2, lines: 1)
  }

  @Test(
    "focused and hidden Table cell Buttons use current captures and retire when disabled",
    arguments: [false, true])
  func nestedCellActionUpdates(indexed: Bool) throws {
    let ledger = TableCellActionLedger()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("UpdatingTableCell", "\(indexed)"),
      size: CellSize(width: 36, height: 16)
    ) {
      UpdatingTableCell(indexed: indexed, ledger: ledger)
    }
    defer { harness.shutdown() }

    func reveal(_ label: String, delta: Int) throws {
      for _ in 0..<48 {
        if harness.frame.contains(label) { return }
        let viewport = try #require(
          harness.runLoop.latestSemanticSnapshot.scrollRoutes.first?.viewportRect)
        let point = Point(
          x: Double(viewport.origin.x + viewport.size.width / 2),
          y: Double(viewport.origin.y + viewport.size.height / 2))
        _ = try harness.scrollPointer(at: point, deltaY: delta)
      }
      try #require(
        harness.frame.contains(label), "wheel did not reveal \(label):\n\(harness.frame)")
    }

    try reveal("Cell6 v0", delta: 1)
    let initialButton = try #require(
      harness.runLoop.latestSemanticSnapshot.accessibilityNodes.first {
        $0.role == .button && $0.label == "Cell6 v0"
      })
    _ = try harness.focus(initialButton.identity)
    let buttonIdentity = initialButton.identity
    #expect(harness.runLoop.focusTracker.currentFocusIdentity == buttonIdentity)
    _ = try harness.pressKey(KeyPress(.character("u"), modifiers: .ctrl))
    #expect(harness.frame.contains("root version=1"), "\(harness.frame)")
    #expect(harness.runLoop.focusTracker.currentFocusIdentity == buttonIdentity)
    #expect(harness.frame.contains("Cell6 v1"), "\(harness.frame)")
    _ = try harness.pressKey(KeyPress(.return))
    #expect(ledger.actions == ["6:1"])

    try reveal("Cell11 v1", delta: 1)
    try #require(!harness.frame.contains("Cell6 v"), "\(harness.frame)")
    _ = try harness.pressKey(KeyPress(.character("u"), modifiers: .ctrl))
    #expect(harness.frame.contains("root version=2"), "\(harness.frame)")
    #expect(!harness.frame.contains("Cell6 v"))
    try reveal("Cell6 v2", delta: -1)
    let revealedButton = try #require(
      harness.runLoop.latestSemanticSnapshot.accessibilityNodes.first {
        $0.role == .button && $0.label == "Cell6 v2"
      })
    _ = try harness.focus(revealedButton.identity)
    _ = try harness.pressKey(KeyPress(.return))
    #expect(ledger.actions == ["6:1", "6:2"])
    let currentButton = try #require(harness.runLoop.focusTracker.currentFocusIdentity)

    _ = try harness.pressKey(KeyPress(.character("d"), modifiers: .ctrl))
    #expect(harness.frame.contains("disabled=true"), "\(harness.frame)")
    #expect(
      !harness.runLoop.latestSemanticSnapshot.focusRegions.contains {
        $0.identity == currentButton
      })
    #expect(harness.runLoop.focusTracker.currentFocusIdentity != currentButton)
    let disabledButton = try #require(
      harness.runLoop.latestSemanticSnapshot.accessibilityNodes.first {
        $0.role == .button && $0.label == "Cell6 v2"
      })
    let disabledTarget = try #require(disabledButton.actionTarget)
    #expect(
      harness.runLoop.handleAccessibilityAction(
        AccessibilityActionRequest(target: disabledTarget, action: .activate)) == .disabled)
    #expect(ledger.actions == ["6:1", "6:2"])
    let liveRow = try #require(
      [5, 7, 4, 8].first { row in
        harness.runLoop.latestSemanticSnapshot.accessibilityNodes.contains {
          $0.role == .button && $0.label == "Cell\(row) v2"
        }
      })
    let liveButton = try #require(
      harness.runLoop.latestSemanticSnapshot.accessibilityNodes.first {
        $0.role == .button && $0.label == "Cell\(liveRow) v2"
      })
    _ = try harness.focus(liveButton.identity)
    _ = try harness.pressKey(KeyPress(.return))
    #expect(ledger.actions == ["6:1", "6:2", "\(liveRow):2"])
  }
}

@MainActor
private struct FreshTallTable: View {
  let indexed: Bool

  var body: some View {
    Group {
      if indexed {
        Table(0..<2, id: \.self, columns: [TableColumn("Value", width: 24)]) { row in
          cell(row)
        }
      } else {
        Table(columns: [TableColumn("Value", width: 24)]) {
          ForEach(0..<2, id: \.self) { row in
            TableRow { cell(row) }
          }
        }
      }
    }.tableHeaders(.hidden).scrollIndicators(.hidden)
  }

  private func cell(_ row: Int) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(0..<(row == 0 ? 4 : 1), id: \.self) { line in
        Text("Fresh\(row):\(line)")
      }
    }
  }
}

@MainActor
private struct EagerMeasuredWindowTable: View {
  let rowLines: Int
  let separators: Bool
  let headers: Bool

  var body: some View {
    Table(selection: .constant(1 as Int?), columns: [TableColumn("Value", width: 24)]) {
      ForEach(0..<4, id: \.self) { row in
        TableRow {
          VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<(row == 1 ? rowLines : 1), id: \.self) { line in
              Text("Window\(row):\(line)")
            }
          }
        }
        .fixedSize(horizontal: false, vertical: true)
        .listRowSeparator(separators ? .visible : .hidden)
        .tag(row)
      }
    }.tableHeaders(headers ? .visible : .hidden)
  }
}

@MainActor
private struct UpdatingTable: View {
  let indexed: Bool
  let multiple: Bool
  @State private var phase = 0
  @State private var isSmall = false
  @State private var selected: Int? = 0
  @State private var members: Set<Int> = []

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      table
        .tableHeaders(.hidden)
        .scrollIndicators(.hidden)
        .frame(height: isSmall ? 8 : 10)
      Text("selected=\(selected ?? -1)")
      Text("members=\(members.sorted())")
    }
    .onKeyPress(.character("g"), modifiers: .ctrl) { _ in
      phase += 1
      return .handled
    }
    .onKeyPress(.character("v"), modifiers: .ctrl) { _ in
      isSmall.toggle()
      return .handled
    }
  }

  @ViewBuilder
  private var table: some View {
    if indexed {
      if multiple {
        Table(0..<12, id: \.self, selection: $members, columns: [TableColumn("Value", width: 24)]) {
          row in
          UpdatingTableRow(row: row, phase: phase)
        }
      } else {
        Table(
          0..<12, id: \.self, selection: $selected, columns: [TableColumn("Value", width: 24)]
        ) {
          row in
          UpdatingTableRow(row: row, phase: phase)
        }
      }
    } else if multiple {
      Table(selection: $members, columns: [TableColumn("Value", width: 24)]) {
        ForEach(0..<12, id: \.self) { row in
          TableRow { UpdatingTableRow(row: row, phase: phase) }.tag(row)
        }
      }
    } else {
      Table(selection: $selected, columns: [TableColumn("Value", width: 24)]) {
        ForEach(0..<12, id: \.self) { row in
          TableRow { UpdatingTableRow(row: row, phase: phase) }.tag(row)
        }
      }
    }
  }
}

@MainActor
private struct UpdatingTableRow: View {
  let row: Int
  let phase: Int

  private var lines: Int {
    guard phase == 1 else { return 1 }
    if row == 5 { return 4 }
    if row == 6 { return 3 }
    return 1
  }

  var body: some View {
    let version = row == 5 || row == 6 ? phase : 0
    VStack(alignment: .leading, spacing: 0) {
      ForEach(0..<lines, id: \.self) { line in
        Text("R\(row)v\(version):\(line)")
      }
    }
  }
}

@MainActor
private final class TableCellActionLedger {
  var actions: [String] = []
}

@MainActor
private struct UpdatingTableCell: View {
  let indexed: Bool
  let ledger: TableCellActionLedger
  @State private var version = 0
  @State private var isDisabled = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      table.tableHeaders(.hidden).scrollIndicators(.hidden).frame(height: 8)
      Text("root version=\(version)")
      Text("disabled=\(isDisabled)")
    }
    .onKeyPress(.character("u"), modifiers: .ctrl) { _ in
      version += 1
      return .handled
    }
    .onKeyPress(.character("d"), modifiers: .ctrl) { _ in
      isDisabled = true
      return .handled
    }
  }

  @ViewBuilder
  private var table: some View {
    if indexed {
      Table(0..<12, id: \.self, columns: [TableColumn("Action", width: 24)]) { row in
        cell(row)
      }
    } else {
      Table(columns: [TableColumn("Action", width: 24)]) {
        ForEach(0..<12, id: \.self) { row in
          TableRow { cell(row) }.id(row)
        }
      }
    }
  }

  private func cell(_ row: Int) -> some View {
    let currentVersion = version
    return Button("Cell\(row) v\(currentVersion)") {
      ledger.actions.append("\(row):\(currentVersion)")
    }
    .disabled(row == 6 && isDisabled)
  }
}
