@_spi(Runners) import SwiftTUI

/// Reconstructs the file previewer's multi-column (miller) selection-move flow
/// without depending on `swift-tui-examples`.
///
/// Several columns of entries sit side by side. Moving the selection updates a
/// single column's highlighted row, and descending into a column re-derives the
/// *next* column's entries from the parent selection (modelling a directory
/// listing changing as you navigate). Sibling columns and chrome stay
/// reuse-eligible, so each selection-move frame is a narrow invalidation over a
/// large, mostly-static tree plus a focus/press change at the clicked entry.
/// This is the committed framework-only stand-in for the missing
/// "collections / multi-column file-browser selection-move" coverage called out
/// in the 2026-06-16 perf signal representativeness pass.
///
/// Column and per-column row counts are fixed by default (smoke-test friendly)
/// but can be overridden with `TERMUI_PERF_BROWSER_COLUMNS` and
/// `TERMUI_PERF_BROWSER_ROWS` to sweep the static-tree size and show whether the
/// per-move cost scales with the columns that are *not* changing.
public struct FileBrowserSelectionScenario: PerfScenario {
  public let name: PerfScenarioName = .fileBrowserSelection
  public let defaultTerminalSize = PerfTerminalSize(columns: 110, rows: 36)
  public let scriptedEvents = [
    "move selection within and across columns of a multi-column browser; descend and ascend"
  ]
  public let visualMarkers = ["File browser workload"]
  public let settlingDescription = "first frame that shows the file browser"

  private static let defaultColumnCount = 3
  private static let defaultRowsPerColumn = 12
  /// Each step is a `(column, row)` the driver clicks. Rows stay in the
  /// always-on-screen band so the script survives row-count sweeps. The path
  /// moves down column 0, descends into column 1, moves there, then column 2.
  private static let selectionPath: [(column: Int, row: Int)] = [
    (0, 1), (0, 2), (0, 3), (1, 0), (1, 2), (2, 1), (1, 1), (0, 0),
  ]

  public init() {}

  @MainActor
  public func run(options: PerfScenarioRunOptions) async throws -> PerfScenarioRunResult {
    let columnCount = Self.resolvedColumnCount()
    let rowsPerColumn = Self.resolvedRowsPerColumn()
    let path = Self.selectionPath.filter { $0.column < columnCount && $0.row < rowsPerColumn }
    return try await PerfScenarioRunner.runWindow(
      scenario: self,
      options: options
    ) {
      PerfFileBrowserView(columnCount: columnCount, rowsPerColumn: rowsPerColumn)
    } drive: { driver in
      _ = try await driver.waitForFrame(containing: "File browser workload")
      let dispatchTime = monotonicSeconds()
      var lastFrame = driver.terminalHost.presentedFrames.last?.frameNumber ?? 0

      for (step, move) in path.enumerated() {
        let cell = try driver.cell(containing: "[\(move.column).\(move.row)]")
        driver.sendClick(at: cell)
        let moved = try await driver.waitForFrame(
          containing: "browser rev \(step + 1)",
          afterFrame: lastFrame
        )
        lastFrame = moved.frameNumber
      }

      let settled = driver.terminalHost.presentedFrames.last
      return [
        PerfEventRecord(
          eventID: "file-browser-selection",
          eventType: "selection_move",
          dispatchTimeSeconds: dispatchTime,
          expectedVisualMarker: "browser rev \(path.count)",
          firstMatchingFrame: lastFrame,
          firstMatchingTimeSeconds: settled?.timestampSeconds ?? dispatchTime,
          finalSettledFrame: settled?.frameNumber ?? lastFrame,
          finalSettledTimeSeconds: settled?.timestampSeconds ?? dispatchTime
        )
      ]
    }
  }

  private static func resolvedColumnCount() -> Int {
    resolvedPositiveInt("TERMUI_PERF_BROWSER_COLUMNS", default: defaultColumnCount)
  }

  private static func resolvedRowsPerColumn() -> Int {
    resolvedPositiveInt("TERMUI_PERF_BROWSER_ROWS", default: defaultRowsPerColumn)
  }

  private static func resolvedPositiveInt(_ key: String, default fallback: Int) -> Int {
    guard let raw = environmentValue(key), let parsed = Int(raw), parsed > 0 else {
      return fallback
    }
    return parsed
  }
}

private struct PerfFileBrowserView: View {
  let columnCount: Int
  let rowsPerColumn: Int

  /// Selected row per column. Mutating one element invalidates only the views
  /// that read it (the column's old/new selected row and the dependent child
  /// column); the rest of the tree stays reuse-eligible.
  @State private var selectedRow: [Int]
  @State private var activeColumn = 0
  @State private var revision = 0

  init(columnCount: Int, rowsPerColumn: Int) {
    self.columnCount = columnCount
    self.rowsPerColumn = rowsPerColumn
    _selectedRow = State(initialValue: Array(repeating: 0, count: columnCount))
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 2) {
        Text("File browser workload")
          .foregroundStyle(.tint)
        Spacer(minLength: 1)
        Text("browser rev \(revision)")
          .foregroundStyle(.muted)
      }
      Divider()
      HStack(alignment: .top, spacing: 1) {
        ForEach(0..<columnCount, id: \.self) { column in
          columnView(column)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      Divider()
      Text("active [\(activeColumn).\(selectedRow[activeColumn])]")
        .foregroundStyle(.separator)
    }
    .padding(1)
    .panel(id: "perf-file-browser")
  }

  private func columnView(_ column: Int) -> some View {
    // The entries a column shows depend on the parent column's selection, so
    // descending re-derives the child listing — without changing the stable
    // "[col.row]" hit token the driver clicks.
    let parentSelection = column == 0 ? 0 : selectedRow[column - 1]
    return VStack(alignment: .leading, spacing: 0) {
      Text("col \(column)/\(parentSelection)")
        .foregroundStyle(.muted)
      ForEach(0..<rowsPerColumn, id: \.self) { row in
        Button("\(selectedRow[column] == row ? "> " : "  ")[\(column).\(row)] d\(parentSelection)")
        {
          selectedRow[column] = row
          activeColumn = column
          revision += 1
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .border(.separator)
  }
}
