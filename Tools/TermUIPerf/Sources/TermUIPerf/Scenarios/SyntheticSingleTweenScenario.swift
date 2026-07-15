@_spi(Runners) import SwiftTUI

/// F149 measurement fixture: one finite property tween in a wide static tree.
///
/// The 176-row default is the program's fixed scale point. Only the opacity on
/// `single tween target` changes after the click; every numbered row is static,
/// so animation-stage cost that scales with the row count is controller overhead
/// rather than authored application work.
public struct SyntheticSingleTweenScenario: PerfScenario {
  public let name: PerfScenarioName = .syntheticSingleTween
  public let defaultTerminalSize = PerfTerminalSize(columns: 80, rows: 40)
  public let scriptedEvents = ["click start tween; observe one finite opacity animation"]
  public let visualMarkers = ["single tween target"]
  public let settlingDescription = "first frame that shows the single-tween target"

  private static let rowCount = 176

  public init() {}

  @MainActor
  public func run(options: PerfScenarioRunOptions) async throws -> PerfScenarioRunResult {
    try await PerfScenarioRunner.runWindow(
      scenario: self,
      options: options
    ) {
      PerfSingleTweenProbeView(rowCount: Self.rowCount)
    } drive: { driver in
      _ = try await driver.waitForFrame(containing: "tween state 0")
      let dispatchTime = monotonicSeconds()
      let frameBeforeClick = driver.terminalHost.presentedFrames.last?.frameNumber ?? 0
      let cell = try driver.cell(containing: "start tween")
      driver.sendClick(at: cell)
      let matchingFrame = try await driver.waitForFrame(
        containing: "tween state 1",
        afterFrame: frameBeforeClick
      )
      return [
        PerfEventRecord(
          eventID: "synthetic-single-tween",
          eventType: "mouse_click",
          dispatchTimeSeconds: dispatchTime,
          expectedVisualMarker: "tween state 1",
          firstMatchingFrame: matchingFrame.frameNumber,
          firstMatchingTimeSeconds: matchingFrame.timestampSeconds,
          finalSettledFrame: matchingFrame.frameNumber,
          finalSettledTimeSeconds: matchingFrame.timestampSeconds
        )
      ]
    }
  }
}

private struct PerfSingleTweenProbeView: View {
  let rowCount: Int

  @State private var dimmed = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("start tween") {
        withAnimation(.linear(duration: .milliseconds(1500))) {
          dimmed.toggle()
        }
      }
      Text("tween state \(dimmed ? 1 : 0)")
      Text("single tween target")
        .opacity(dimmed ? 0.2 : 1)
      ForEach(Array(0..<rowCount), id: \.self) { row in
        Text("static row \(row)")
      }
    }
    .padding(1)
  }
}
