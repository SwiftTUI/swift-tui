@_spi(Runners) import SwiftTUI

/// F173 vehicle: a direct-data `Table` of 1,000 rows × 4 columns. Finite
/// frames resolve and place only the selected viewport band, while the two
/// auto-width columns exercise visible-window width discovery.
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
  // Keep headroom for scaling probes that set the row-count override to 10k.
  public let initialFrameTimeout: Duration = .seconds(120)

  private static let defaultRowCount = 1_000

  public init() {}

  @MainActor
  public func run(options: PerfScenarioRunOptions) async throws -> PerfScenarioRunResult {
    let rowCount = Self.resolvedRowCount()
    let usesEagerBuilder = Self.usesEagerBuilder()
    return try await PerfScenarioRunner.runWindow(
      scenario: self,
      options: options
    ) {
      PerfTableView(rowCount: rowCount, usesEagerBuilder: usesEagerBuilder)
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

  private static func usesEagerBuilder() -> Bool {
    environmentValue("TERMUI_PERF_COLLECTION_SOURCE_MODE") == "eager"
  }
}

private struct PerfTableView: View {
  let rowCount: Int
  let usesEagerBuilder: Bool

  @State private var selection: Int? = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Table workload")
        .foregroundStyle(.tint)
      // Deterministic mirror of the selection — independent of row chrome —
      // so the driver can settle each selection step.
      Text("sel:\(selection ?? -1)|")
      if usesEagerBuilder {
        Table(selection: $selection, columns: Self.columns) {
          ForEach(0..<rowCount, id: \.self) { index in
            TableRow {
              cells(index)
            }
            .tag(index)
          }
        }
        .frame(height: 26)
        .border(.separator)
      } else {
        Table(
          0..<rowCount,
          id: \.self,
          selection: $selection,
          columns: Self.columns
        ) { index in
          cells(index)
        }
        .frame(height: 26)
        .border(.separator)
      }
    }
    .padding(1)
  }

  private static let columns: [TableColumn] = [
    .init("Name", width: 14),
    .init("Kind"),
    .init("Size", width: 8, alignment: .trailing),
    .init("Note"),
  ]

  @ViewBuilder
  private func cells(_ index: Int) -> some View {
    Text("trow \(index)")
    Text("kind-\(index % 7)")
    Text("\(index * 3)")
    Text("note \(index % 13)")
  }
}
