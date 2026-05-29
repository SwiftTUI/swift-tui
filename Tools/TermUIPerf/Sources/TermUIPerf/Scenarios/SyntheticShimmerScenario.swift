@_spi(Runners) import SwiftTUI

/// Reproduces H5 (task-progress / TextLayoutCache churn): a TimelineView that
/// mints fresh text content every tick, producing per-tick text-layout-key
/// misses and continuous committed frames.
public struct SyntheticShimmerScenario: PerfScenario {
  public let name: PerfScenarioName = .syntheticTextShimmer
  public let defaultTerminalSize = PerfTerminalSize(columns: 90, rows: 20)
  public let scriptedEvents = ["observe shimmer text churn idle frames"]
  public let visualMarkers = ["shimmer"]
  public let settlingDescription = "first frame that contains shimmer"

  public init() {}

  @MainActor
  public func run(options: PerfScenarioRunOptions) async throws -> PerfScenarioRunResult {
    try await PerfScenarioRunner.runWindow(
      scenario: self,
      options: options
    ) {
      PerfShimmerProbeView()
    } drive: { driver in
      let frame = try await driver.waitForFrame(containing: "shimmer")
      let dispatchTime = monotonicSeconds()
      try? await Task.sleep(for: .seconds(3))
      return [
        PerfEventRecord(
          eventID: "synthetic-text-shimmer-settled",
          eventType: "idle",
          dispatchTimeSeconds: dispatchTime,
          expectedVisualMarker: "shimmer",
          firstMatchingFrame: frame.frameNumber,
          firstMatchingTimeSeconds: frame.timestampSeconds,
          finalSettledFrame: driver.terminalHost.presentedFrames.last?.frameNumber
            ?? frame.frameNumber,
          finalSettledTimeSeconds: driver.terminalHost.presentedFrames.last?.timestampSeconds
            ?? frame.timestampSeconds
        )
      ]
    }
  }
}

private struct PerfShimmerProbeView: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      TimelineView(.animation) { context in
        let millis =
          Int(context.instant.offset.components.attoseconds / 1_000_000_000_000_000)
          &+ Int(context.instant.offset.components.seconds &* 1000)
        Text("shimmer \(millis)")
      }
    }
    .padding(1)
  }
}
