@_spi(Runners) import SwiftTUI

/// F173 vehicle: a direct-data `List` over 1,000 elements by default. The
/// initializer exposes a total indexed source, so finite frames realize only
/// the visible band plus bounded overscan while the selection walk repeatedly
/// shifts that band over an unchanged data source.
///
/// A `sel:<tag>|` mirror line gives the driver a deterministic settle marker
/// for selection moves that is independent of row focus chrome. Row count is
/// `TERMUI_PERF_LAZY_LIST_ROWS`-overridable for scaling probes. The default
/// is 1k because that is the largest scale HEAD can drive today: the Stage-0
/// doubling probe measured total-CPU ratios of 2.39x (500->1k) and 2.89x
/// (1k->2k) — a dominating quadratic term — and a 10k initial frame does not
/// present within 120 seconds. Flipping the default (and name) to 10k is a
/// proposal 2026-07-13-002 Stage-2 acceptance criterion.
public struct LazyList1KScenario: PerfScenario {
  public let name: PerfScenarioName = .lazyList1K
  public let defaultTerminalSize = PerfTerminalSize(columns: 80, rows: 32)
  public let scriptedEvents = [
    "scroll bursts over a 1k-row List, then arrow-key selection moves"
  ]
  public let visualMarkers = ["lrow 0"]
  public let settlingDescription = "first frame showing the list's first row"
  // Keep headroom for scaling probes that set the row-count override to 10k.
  public let initialFrameTimeout: Duration = .seconds(60)

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
      PerfLazyListView(rowCount: rowCount, usesEagerBuilder: usesEagerBuilder)
    } drive: { driver in
      // Initial render: direct-data source setup plus the first viewport.
      _ = try await driver.waitForFrame(containing: "lrow 0", timeout: .seconds(120))
      var lastFrame = driver.terminalHost.presentedFrames.last?.frameNumber ?? 0
      var events: [PerfEventRecord] = []

      // Click a visible row: activation writes the selection binding (and
      // focuses the row for the arrow-key leg below).
      let clickDispatch = monotonicSeconds()
      let rowCell = try driver.cell(containing: "lrow 3")
      driver.sendClick(at: rowCell)
      let clicked = try await driver.waitForFrame(
        containing: "sel:3|",
        afterFrame: lastFrame,
        timeout: .seconds(60)
      )
      lastFrame = clicked.frameNumber
      events.append(
        PerfEventRecord(
          eventID: "lazy-list-click-select",
          eventType: "pointer_select",
          dispatchTimeSeconds: clickDispatch,
          expectedVisualMarker: "sel:3|",
          firstMatchingFrame: clicked.frameNumber,
          firstMatchingTimeSeconds: clicked.timestampSeconds,
          finalSettledFrame: clicked.frameNumber,
          finalSettledTimeSeconds: clicked.timestampSeconds
        )
      )

      // Wheel scroll over the list steps the bound selection (List's pointer
      // contract) — each step is an interaction frame over the unchanged
      // 1k-row source.
      let scrollDispatch = monotonicSeconds()
      driver.sendScroll(deltaY: 6, at: rowCell)
      let scrolled = try await driver.waitForFrame(
        containing: "sel:9|",
        afterFrame: lastFrame,
        timeout: .seconds(60)
      )
      lastFrame = scrolled.frameNumber
      events.append(
        PerfEventRecord(
          eventID: "lazy-list-scroll-select",
          eventType: "scroll",
          dispatchTimeSeconds: scrollDispatch,
          expectedVisualMarker: "sel:9|",
          firstMatchingFrame: scrolled.frameNumber,
          firstMatchingTimeSeconds: scrolled.timestampSeconds,
          finalSettledFrame: scrolled.frameNumber,
          finalSettledTimeSeconds: scrolled.timestampSeconds
        )
      )

      // Deep selection walk: repeated wheel bursts push the selection (and
      // the follow-focus viewport) well past the initial window, so the
      // entering/leaving-row work is exercised, not just the first page.
      // (Keyboard arrows deliberately not used: Tab's focus arrival snaps the
      // selection to the arrived row, which makes step expectations
      // machine-dependent.)
      let walkDispatch = monotonicSeconds()
      var settledFrame = scrolled
      for burst in 1...5 {
        driver.sendScroll(deltaY: 6, at: rowCell)
        settledFrame = try await driver.waitForFrame(
          containing: "sel:\(9 + burst * 6)|",
          afterFrame: lastFrame,
          timeout: .seconds(60)
        )
        lastFrame = settledFrame.frameNumber
      }
      events.append(
        PerfEventRecord(
          eventID: "lazy-list-selection-walk",
          eventType: "scroll",
          dispatchTimeSeconds: walkDispatch,
          expectedVisualMarker: "sel:39|",
          firstMatchingFrame: settledFrame.frameNumber,
          firstMatchingTimeSeconds: settledFrame.timestampSeconds,
          finalSettledFrame: settledFrame.frameNumber,
          finalSettledTimeSeconds: settledFrame.timestampSeconds
        )
      )
      return events
    }
  }

  private static func resolvedRowCount() -> Int {
    guard let raw = environmentValue("TERMUI_PERF_LAZY_LIST_ROWS"),
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

private struct PerfLazyListView: View {
  let rowCount: Int
  let usesEagerBuilder: Bool

  @State private var selection: Int? = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Lazy list workload")
        .foregroundStyle(.tint)
      // Deterministic mirror of the selection — independent of row focus
      // chrome — so the driver can settle each selection move.
      Text("sel:\(selection ?? -1)|")
      if usesEagerBuilder {
        List(selection: $selection) {
          ForEach(0..<rowCount, id: \.self) { index in
            row(index).tag(index)
          }
        }
        .frame(height: 24)
        .border(.separator)
      } else {
        List(0..<rowCount, id: \.self, selection: $selection) { index in
          row(index)
        }
        .frame(height: 24)
        .border(.separator)
      }
    }
    .padding(1)
  }

  private func row(_ index: Int) -> some View {
    HStack(spacing: 1) {
      Text("lrow \(index)")
      Spacer(minLength: 1)
      Text("meta \(index % 97)")
        .foregroundStyle(.separator)
    }
  }
}
