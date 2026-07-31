@_spi(Runners) import SwiftTUI

/// Program Stage 0, WP-2: **open-loop** scroll at a fixed 60 Hz cadence.
///
/// Notches go out on schedule whether or not the last one has been answered.
/// That is the only way to see back-pressure: a closed loop refuses to send
/// the next input until the runtime has caught up, so it can never observe a
/// runtime that has not. What this scenario produces — coalesced multi-input
/// frames, superseded presents, a growing input→commit tail — is invisible to
/// every other scenario in the suite.
///
/// Per-notch latency is deliberately **not** measured here by marker matching;
/// it is read from the runtime's own `input_to_commit_*` columns and from
/// `presents.tsv`. A per-notch marker wait would close the loop again.
///
/// **Run this in an async render mode.** Under `--mode sync` the drive is not
/// actually open-loop: the synchronous frame driver drains to quiescence
/// inside the injection task's own suspension points, so every notch gets its
/// own frame and the scenario reports no back-pressure at all. Measured on a
/// 200-row list in debug, 60 notches at 16.6 ms:
///
/// | mode | frames | frames coalescing >1 input | input→commit p50 |
/// | --- | --- | --- | --- |
/// | `sync` | 61 | 0 | 45 ms |
/// | `async` | 22 | 20 (up to 3 inputs) | 453 ms |
///
/// Same code, same cadence, an order of magnitude apart — because only one of
/// them is a race. The default mode is async for exactly this reason; the sync
/// number is not a smaller version of the async one, it is a measurement of
/// something else.
public struct ScrollCadence60HzScenario: PerfScenario {
  public let name: PerfScenarioName = .scrollCadence60Hz
  public let defaultTerminalSize = PerfTerminalSize(columns: 80, rows: 32)
  public let scriptedEvents = [
    "120 wheel notches injected at 16.6 ms with no settle between them"
  ]
  public let visualMarkers = ["srow 0"]
  public let settlingDescription = "first frame showing the collection's first row"
  public let initialFrameTimeout: Duration = .seconds(60)

  private static let defaultNotchCount = 120
  private static let defaultCadence = Duration.microseconds(16_600)

  public init() {}

  @MainActor
  public func run(options: PerfScenarioRunOptions) async throws -> PerfScenarioRunResult {
    let rowCount = ScrollScenarioContent.rowCount()
    let notchCount = Self.resolvedNotchCount()
    let cadence = Self.resolvedCadence()
    return try await PerfScenarioRunner.runWindow(
      scenario: self,
      options: options
    ) {
      PerfScrollListView(rowCount: rowCount)
    } drive: { driver in
      _ = try await driver.waitForFrame(containing: "srow 0", timeout: .seconds(120))
      let scrollCell = try driver.cell(containing: "srow 2")

      let dispatch = monotonicSeconds()
      await driver.driveScroll(cadence: cadence, notches: notchCount, at: scrollCell)
      // The settle tail: everything the burst left queued lands here, and it
      // is part of the cost, so it is inside the measured window.
      await driver.waitForQuiescence(idle: .milliseconds(400), timeout: .seconds(60))
      let settled = driver.terminalHost.presentedFrames.last

      return [
        PerfEventRecord(
          eventID: "scroll-cadence-burst",
          eventType: "scroll",
          dispatchTimeSeconds: dispatch,
          expectedVisualMarker: "<open-loop burst; see runtime latency columns>",
          firstMatchingFrame: settled?.frameNumber,
          firstMatchingTimeSeconds: settled?.timestampSeconds,
          finalSettledFrame: settled?.frameNumber,
          finalSettledTimeSeconds: settled?.timestampSeconds
        )
      ]
    }
  }

  private static func resolvedNotchCount() -> Int {
    guard let raw = environmentValue("SWIFTTUI_PERF_SCROLL_CADENCE_NOTCHES"),
      let parsed = Int(raw),
      parsed > 0
    else {
      return defaultNotchCount
    }
    return parsed
  }

  private static func resolvedCadence() -> Duration {
    guard let raw = environmentValue("SWIFTTUI_PERF_SCROLL_CADENCE_MICROSECONDS"),
      let parsed = Int(raw),
      parsed > 0
    else {
      return defaultCadence
    }
    return .microseconds(parsed)
  }
}
