@_spi(Runners) import SwiftTUI

/// Program Stage 0, WP-2: one momentum fling, run to exhaustion.
///
/// The third drive shape, and the only one where the *runtime* is the input
/// source: after the release, frames come from the momentum controller's
/// 33 ms deadline re-arm, not from the user. Those frames answer no input at
/// all, so they report empty latency columns by construction — what this
/// scenario measures is per-frame cost during decay, and how long the decay
/// keeps the pipeline busy after the finger is gone.
public struct ScrollFlingMomentumScenario: PerfScenario {
  public let name: PerfScenarioName = .scrollFlingMomentum
  public let defaultTerminalSize = PerfTerminalSize(columns: 80, rows: 32)
  public let scriptedEvents = [
    "one fast upward flick over a windowed collection, then momentum decay"
  ]
  public let visualMarkers = ["srow 0"]
  public let settlingDescription = "first frame showing the collection's first row"
  public let initialFrameTimeout: Duration = .seconds(60)

  private static let flingCells = 16
  private static let flingSamples = 8

  public init() {}

  @MainActor
  public func run(options: PerfScenarioRunOptions) async throws -> PerfScenarioRunResult {
    let rowCount = ScrollScenarioContent.rowCount()
    let flingDuration = Self.resolvedFlingDuration()
    return try await PerfScenarioRunner.runWindow(
      scenario: self,
      options: options
    ) {
      PerfScrollListView(rowCount: rowCount)
    } drive: { driver in
      _ = try await driver.waitForFrame(containing: "srow 0", timeout: .seconds(120))
      // Start low in the viewport so the upward flick has room to travel.
      let anchor = try driver.cell(containing: "srow 2")
      let origin = CellPoint(x: anchor.x, y: anchor.y + Self.flingCells)

      let dispatch = monotonicSeconds()
      await driver.sendFling(
        from: origin,
        cells: Self.flingCells,
        over: flingDuration,
        samples: Self.flingSamples
      )
      // Momentum re-arms a deadline every 33 ms until it decays to rest; the
      // quiescence window is what "exhaustion" means here.
      await driver.waitForQuiescence(idle: .milliseconds(500), timeout: .seconds(60))
      let settled = driver.terminalHost.presentedFrames.last

      return [
        PerfEventRecord(
          eventID: "scroll-fling",
          eventType: "scroll",
          dispatchTimeSeconds: dispatch,
          expectedVisualMarker: "<fling release, then momentum to rest>",
          firstMatchingFrame: settled?.frameNumber,
          firstMatchingTimeSeconds: settled?.timestampSeconds,
          finalSettledFrame: settled?.frameNumber,
          finalSettledTimeSeconds: settled?.timestampSeconds
        )
      ]
    }
  }

  private static func resolvedFlingDuration() -> Duration {
    guard let raw = environmentValue("SWIFTTUI_PERF_SCROLL_FLING_MICROSECONDS"),
      let parsed = Int(raw),
      parsed > 0
    else {
      return .milliseconds(48)
    }
    return .microseconds(parsed)
  }
}
