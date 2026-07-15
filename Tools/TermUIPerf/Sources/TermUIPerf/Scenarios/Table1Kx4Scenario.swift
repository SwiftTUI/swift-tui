@_spi(Runners) import SwiftTUI

/// Proposal 2026-07-13-002 Stage-0 vehicle: a `Table` of 1,000 rows × 4
/// columns (two fixed-width, two auto-width — auto columns are the Stage-3
/// full-materialization driver: their widths today consume every off-screen
/// cell). The driver settles the initial render, then steps the bound
/// selection with wheel scroll (Table's pointer contract), producing
/// interaction frames over the unchanged 1k-row source.
///
/// A `sel:<tag>|` mirror line gives the driver a deterministic settle marker
/// independent of row chrome. Row count is `TERMUI_PERF_TABLE_ROWS`-
/// overridable for scaling probes; the default stays at the scenario's named
/// 1k so committed baselines mean what the name says.
public struct Table1Kx4Scenario: PerfScenario {
  public let name: PerfScenarioName = .table1Kx4
  public let defaultTerminalSize = PerfTerminalSize(columns: 96, rows: 32)
  public let scriptedEvents = ["wheel-step selection through a 1000-row, 4-column table"]
  public let visualMarkers = ["trow 0"]
  public let settlingDescription = "first frame showing the table's first row"
  // The initial frame IS the workload: a full 1k×4 materialization.
  public let initialFrameTimeout: Duration = .seconds(120)

  private static let defaultRowCount = 1_000

  public init() {}

  @MainActor
  public func run(options: PerfScenarioRunOptions) async throws -> PerfScenarioRunResult {
    let rowCount = Self.resolvedRowCount()
    return try await PerfScenarioRunner.runWindow(
      scenario: self,
      options: options
    ) {
      PerfTableView(rowCount: rowCount)
    } drive: { driver in
      _ = try await driver.waitForFrame(containing: "trow 0", timeout: .seconds(120))
      let lastFrame = driver.terminalHost.presentedFrames.last?.frameNumber ?? 0

      let scrollDispatch = monotonicSeconds()
      let tableCell = try driver.cell(containing: "trow 3")
      driver.sendScroll(deltaY: 6, at: tableCell)
      let scrolled = try await driver.waitForFrame(
        containing: "sel:6|",
        afterFrame: lastFrame,
        timeout: .seconds(60)
      )
      return [
        PerfEventRecord(
          eventID: "table-scroll-select",
          eventType: "scroll",
          dispatchTimeSeconds: scrollDispatch,
          expectedVisualMarker: "sel:6|",
          firstMatchingFrame: scrolled.frameNumber,
          firstMatchingTimeSeconds: scrolled.timestampSeconds,
          finalSettledFrame: scrolled.frameNumber,
          finalSettledTimeSeconds: scrolled.timestampSeconds
        )
      ]
    }
  }

  private static func resolvedRowCount() -> Int {
    guard let raw = environmentValue("TERMUI_PERF_TABLE_ROWS"),
      let parsed = Int(raw),
      parsed > 0
    else {
      return defaultRowCount
    }
    return parsed
  }
}

private struct PerfTableView: View {
  let rowCount: Int

  @State private var selection = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Table workload")
        .foregroundStyle(.tint)
      // Deterministic mirror of the selection — independent of row chrome —
      // so the driver can settle each selection step.
      Text("sel:\(selection)|")
      Table(
        selection: $selection,
        columns: [
          .init("Name", width: 14),
          .init("Kind"),
          .init("Size", width: 8, alignment: .trailing),
          .init("Note"),
        ]
      ) {
        ForEach(0..<rowCount, id: \.self) { index in
          TableRow {
            Text("trow \(index)")
            Text("kind-\(index % 7)")
            Text("\(index * 3)")
            Text("note \(index % 13)")
          }
          .tag(index)
        }
      }
      .frame(height: 26)
      .border(.separator)
    }
    .padding(1)
  }
}
