@_spi(Runners) import SwiftTUI

/// Program Stage 0, WP-2: per-notch **closed-loop** scroll latency over a
/// windowed collection — the Class-A vehicle.
///
/// Each notch waits for the frame that answers it before the next goes out, so
/// every notch produces one clean input→present sample and the run measures a
/// runtime that is never behind. That is the best case; `scroll-cadence-60hz`
/// measures what happens when it is.
public struct ScrollNotchLatencyScenario: PerfScenario {
  public let name: PerfScenarioName = .scrollNotchLatency
  public let defaultTerminalSize = PerfTerminalSize(columns: 80, rows: 32)
  public let scriptedEvents = [
    "200 single wheel notches over a windowed collection, one settle each"
  ]
  public let visualMarkers = ["srow 0"]
  public let settlingDescription = "first frame showing the collection's first row"
  public let initialFrameTimeout: Duration = .seconds(60)

  private static let notchCount = 200

  public init() {}

  @MainActor
  public func run(options: PerfScenarioRunOptions) async throws -> PerfScenarioRunResult {
    let rowCount = ScrollScenarioContent.rowCount()
    let notchCount = min(Self.resolvedNotchCount(), max(1, rowCount / 2))
    return try await PerfScenarioRunner.runWindow(
      scenario: self,
      options: options
    ) {
      PerfScrollListView(rowCount: rowCount)
    } drive: { driver in
      _ = try await driver.waitForFrame(containing: "srow 0", timeout: .seconds(120))
      let scrollCell = try driver.cell(containing: "srow 2")
      var lastFrame = driver.terminalHost.presentedFrames.last?.frameNumber ?? 0
      var events: [PerfEventRecord] = []

      for notch in 0..<notchCount {
        let dispatch = monotonicSeconds()
        let settled = try await driver.scrollAwaitingFrame(
          deltaY: 1,
          at: scrollCell,
          afterFrame: lastFrame,
          timeout: .seconds(30)
        )
        lastFrame = settled.frameNumber
        events.append(
          PerfEventRecord(
            eventID: "scroll-notch-\(notch)",
            eventType: "scroll",
            dispatchTimeSeconds: dispatch,
            expectedVisualMarker: "<next presented frame>",
            firstMatchingFrame: settled.frameNumber,
            firstMatchingTimeSeconds: settled.timestampSeconds,
            finalSettledFrame: settled.frameNumber,
            finalSettledTimeSeconds: settled.timestampSeconds
          )
        )
      }
      return events
    }
  }

  private static func resolvedNotchCount() -> Int {
    guard let raw = environmentValue("SWIFTTUI_PERF_SCROLL_NOTCHES"),
      let parsed = Int(raw),
      parsed > 0
    else {
      return notchCount
    }
    return parsed
  }
}
