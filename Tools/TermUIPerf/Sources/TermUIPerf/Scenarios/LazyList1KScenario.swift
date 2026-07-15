@_spi(Runners) import SwiftTUI

/// Proposal 2026-07-13-002 Stage-0 vehicle: a `List` over a 1,000-element (by default)
/// indexed `ForEach` source — the shape whose every-element resolve/measure
/// the viewport-true lazy collections program targets. The driver settles the
/// initial render (the headline full-materialization cost), then scrolls the
/// viewport (re-layout + window shift), then moves selection with arrow keys
/// (interaction frames over an unchanged data source).
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
  // The initial frame IS the workload: a full 1k-row materialization —
  // seconds in debug, beyond the runner's 2-second default.
  public let initialFrameTimeout: Duration = .seconds(60)

  private static let defaultRowCount = 1_000

  public init() {}

  @MainActor
  public func run(options: PerfScenarioRunOptions) async throws -> PerfScenarioRunResult {
    let rowCount = Self.resolvedRowCount()
    return try await PerfScenarioRunner.runWindow(
      scenario: self,
      options: options
    ) {
      PerfLazyListView(rowCount: rowCount)
    } drive: { driver in
      // Initial render: the full-materialization cost the program attacks.
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
}

private struct PerfLazyListView: View {
  let rowCount: Int

  @State private var selection = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Lazy list workload")
        .foregroundStyle(.tint)
      // Deterministic mirror of the selection — independent of row focus
      // chrome — so the driver can settle each selection move.
      Text("sel:\(selection)|")
      List(selection: $selection) {
        ForEach(0..<rowCount, id: \.self) { index in
          HStack(spacing: 1) {
            Text("lrow \(index)")
            Spacer(minLength: 1)
            Text("meta \(index % 97)")
              .foregroundStyle(.separator)
          }
          .tag(index)
        }
      }
      .frame(height: 24)
      .border(.separator)
    }
    .padding(1)
  }
}
