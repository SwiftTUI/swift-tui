@_spi(Runners) import SwiftTUI

/// Reproduces H4: continuous visible damage from a `.repeatForever` animation
/// that keeps repainting on-screen cells every tick.
public struct SyntheticRepeatForeverScenario: PerfScenario {
  public let name: PerfScenarioName = .syntheticContinuousAnimation
  public let defaultTerminalSize = PerfTerminalSize(columns: 90, rows: 20)
  public let scriptedEvents = ["observe continuous repeat-forever animation idle frames"]
  public let visualMarkers = ["continuous-anim"]
  public let settlingDescription = "first frame that contains continuous-anim"

  public init() {}

  @MainActor
  public func run(options: PerfScenarioRunOptions) async throws -> PerfScenarioRunResult {
    try await PerfScenarioRunner.runWindow(
      scenario: self,
      options: options
    ) {
      PerfRepeatForeverProbeView()
    } drive: { driver in
      let frame = try await driver.waitForFrame(containing: "continuous-anim")
      let dispatchTime = monotonicSeconds()
      try? await Task.sleep(for: .seconds(3))
      return [
        PerfEventRecord(
          eventID: "synthetic-continuous-animation-settled",
          eventType: "idle",
          dispatchTimeSeconds: dispatchTime,
          expectedVisualMarker: "continuous-anim",
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

private struct PerfRepeatForeverProbeView: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("continuous-anim")
      Spinner(.brailleLoop)
    }
    .padding(1)
  }
}
