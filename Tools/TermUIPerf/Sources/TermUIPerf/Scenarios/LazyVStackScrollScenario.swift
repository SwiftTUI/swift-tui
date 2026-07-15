@_spi(Runners) import SwiftTUI

/// Proposal 2026-07-13-002 Stage-2 vehicle (design note 2026-07-14-004): a
/// ScrollView-hosted `LazyVStack` over an indexed `ForEach` source — the ONLY
/// committed scenario that exercises `ForEachIndexedChildSource` (List/Table
/// resolve eagerly, so `lazy-list-1k`/`table-1kx4` never touch the lazy
/// path). The driver settles the initial render (the F144 full-realization
/// cost: measure materializes and ideal-measures every row today), then
/// drives wheel bursts that move the VIEWPORT — not a selection binding, the
/// List-scenario trap — so window-shift work is exercised directly.
///
/// Row count is `TERMUI_PERF_LAZY_VSTACK_ROWS`-overridable for scaling
/// probes. The default is 10k — the Stage-2 exit criterion, flipped when
/// windowed measurement landed: the pre-windowing HEAD could not present a
/// 10k first frame within 120 seconds; the windowed pipeline completes the
/// whole 10k scenario in ~1.3s (debug).
public struct LazyVStackScrollScenario: PerfScenario {
  public let name: PerfScenarioName = .lazyVStackScroll
  public let defaultTerminalSize = PerfTerminalSize(columns: 80, rows: 32)
  public let scriptedEvents = [
    "wheel viewport bursts over a lazy vertical stack"
  ]
  public let visualMarkers = ["vrow 0"]
  public let settlingDescription = "first frame showing the lazy stack's first row"
  // The initial frame IS the workload: full realization + ideal measurement
  // of every row — beyond the runner's 2-second default at measurement scale.
  public let initialFrameTimeout: Duration = .seconds(60)

  private static let defaultRowCount = 10_000
  /// Each burst scrolls farther than the viewport is tall, so the settle
  /// marker (the burst's new top row) is never visible before the burst.
  private static let burstRows = 30

  public init() {}

  @MainActor
  public func run(options: PerfScenarioRunOptions) async throws -> PerfScenarioRunResult {
    let rowCount = Self.resolvedRowCount()
    return try await PerfScenarioRunner.runWindow(
      scenario: self,
      options: options
    ) {
      PerfLazyVStackScrollView(rowCount: rowCount)
    } drive: { driver in
      // Initial render: the F144 full-materialization cost.
      _ = try await driver.waitForFrame(containing: "vrow 0", timeout: .seconds(120))
      var lastFrame = driver.terminalHost.presentedFrames.last?.frameNumber ?? 0
      var events: [PerfEventRecord] = []
      let scrollCell = try driver.cell(containing: "vrow 2")

      // First viewport jump past the initially realized window.
      let firstDispatch = monotonicSeconds()
      driver.sendScroll(deltaY: Self.burstRows, at: scrollCell)
      let firstSettled = try await driver.waitForFrame(
        containing: "vrow \(Self.burstRows)",
        afterFrame: lastFrame,
        timeout: .seconds(60)
      )
      lastFrame = firstSettled.frameNumber
      events.append(
        PerfEventRecord(
          eventID: "lazy-vstack-first-scroll",
          eventType: "scroll",
          dispatchTimeSeconds: firstDispatch,
          expectedVisualMarker: "vrow \(Self.burstRows)",
          firstMatchingFrame: firstSettled.frameNumber,
          firstMatchingTimeSeconds: firstSettled.timestampSeconds,
          finalSettledFrame: firstSettled.frameNumber,
          finalSettledTimeSeconds: firstSettled.timestampSeconds
        )
      )

      // Deep viewport walk: repeated bursts push the window well past the
      // initial page, exercising entering/leaving-row work each time.
      let walkDispatch = monotonicSeconds()
      var settledFrame = firstSettled
      for burst in 2...6 {
        driver.sendScroll(deltaY: Self.burstRows, at: scrollCell)
        settledFrame = try await driver.waitForFrame(
          containing: "vrow \(burst * Self.burstRows)",
          afterFrame: lastFrame,
          timeout: .seconds(60)
        )
        lastFrame = settledFrame.frameNumber
      }
      events.append(
        PerfEventRecord(
          eventID: "lazy-vstack-viewport-walk",
          eventType: "scroll",
          dispatchTimeSeconds: walkDispatch,
          expectedVisualMarker: "vrow \(6 * Self.burstRows)",
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
    guard let raw = environmentValue("TERMUI_PERF_LAZY_VSTACK_ROWS"),
      let parsed = Int(raw),
      parsed > 0
    else {
      return defaultRowCount
    }
    // The deep walk scrolls to row 6 * burstRows; keep every settle marker
    // inside the dataset so pinned-down smoke sweeps stay drivable.
    return max(parsed, 6 * burstRows + 1)
  }
}

private struct PerfLazyVStackScrollView: View {
  let rowCount: Int

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Lazy vstack scroll workload")
        .foregroundStyle(.tint)
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach(0..<rowCount, id: \.self) { index in
            HStack(spacing: 1) {
              Text("vrow \(index)")
              Spacer(minLength: 1)
              Text("meta \(index % 89)")
                .foregroundStyle(.separator)
            }
          }
        }
      }
      .frame(height: 24)
      .border(.separator)
    }
    .padding(1)
  }
}
