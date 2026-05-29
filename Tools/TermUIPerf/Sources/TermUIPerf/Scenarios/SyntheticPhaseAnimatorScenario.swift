@_spi(Runners) import SwiftTUI

/// Reproduces H1: an off-screen perpetual PhaseAnimator that drives many
/// committed frames while producing near-zero visible damage (the animator
/// sits below the terminal fold, so none of its ticks touch visible cells).
public struct SyntheticPhaseAnimatorScenario: PerfScenario {
  public let name: PerfScenarioName = .syntheticOffscreenPhaseAnimator
  public let defaultTerminalSize = PerfTerminalSize(columns: 90, rows: 38)
  public let scriptedEvents = ["observe off-screen phase animator idle frames"]
  public let visualMarkers = ["fold-top"]
  public let settlingDescription = "first frame that contains fold-top"

  public init() {}

  @MainActor
  public func run(options: PerfScenarioRunOptions) async throws -> PerfScenarioRunResult {
    try await PerfScenarioRunner.runWindow(
      scenario: self,
      options: options
    ) {
      PerfOffscreenPhaseProbeView()
    } drive: { driver in
      let frame = try await driver.waitForFrame(containing: "fold-top")
      let dispatchTime = monotonicSeconds()
      try? await Task.sleep(for: .seconds(3))
      return [
        PerfEventRecord(
          eventID: "synthetic-offscreen-phase-animator-settled",
          eventType: "idle",
          dispatchTimeSeconds: dispatchTime,
          expectedVisualMarker: "fold-top",
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

private struct PerfOffscreenPhaseProbeView: View {
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        Text("fold-top")
        ForEach(1..<44, id: \.self) { index in
          Text("filler row \(index)")
        }
        PhaseAnimator([PulsePhase.dim, .bright]) { phase in
          Text("offscreen-pulse")
            .foregroundStyle(phase.color)
        } animation: { _ in
          .easeInOut(duration: .milliseconds(600))
        }
      }
    }
  }
}

private enum PulsePhase: Equatable, Sendable {
  case dim
  case bright

  var color: Color {
    switch self {
    case .dim: .blue
    case .bright: .red
    }
  }
}
