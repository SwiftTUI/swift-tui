@_spi(Runners) import SwiftTUI

public struct GalleryAnimationClickScenario: PerfScenario {
  public let name: PerfScenarioName = .galleryAnimationClick
  public let defaultTerminalSize = PerfTerminalSize(columns: 110, rows: 38)
  public let scriptedEvents = ["click linear animation button"]
  public let visualMarkers = ["curve: linear"]
  public let settlingDescription = "first frame whose animation section reports curve: linear"

  public init() {}

  @MainActor
  public func run(options: PerfScenarioRunOptions) async throws -> PerfScenarioRunResult {
    try await PerfScenarioRunner.runWindow(
      scenario: self,
      options: options
    ) {
      PerfAnimationProbeView()
    } drive: { driver in
      _ = try await driver.waitForFrame(containing: "linear")
      let cell = try driver.cell(containing: "linear")
      let dispatchTime = monotonicSeconds()
      let frameBeforeClick = driver.terminalHost.presentedFrames.last?.frameNumber ?? 0
      driver.sendClick(at: cell)
      let matchingFrame = try await driver.waitForFrame(
        containing: "curve: linear",
        afterFrame: frameBeforeClick
      )
      return [
        PerfEventRecord(
          eventID: "gallery-animation-linear-click",
          eventType: "mouse_click",
          dispatchTimeSeconds: dispatchTime,
          expectedVisualMarker: "curve: linear",
          firstMatchingFrame: matchingFrame.frameNumber,
          firstMatchingTimeSeconds: matchingFrame.timestampSeconds,
          finalSettledFrame: matchingFrame.frameNumber,
          finalSettledTimeSeconds: matchingFrame.timestampSeconds
        )
      ]
    }
  }
}

private struct PerfAnimationProbeView: View {
  @State private var colorBlue = false
  @State private var curveLabel = "(tap a curve)"

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Animation perf probe").foregroundStyle(.muted)
      Text("curve: \(curveLabel)")
        .foregroundStyle(colorBlue ? Color.blue : Color.red)
      Button("linear") {
        withAnimation(.linear(duration: .milliseconds(1500))) {
          colorBlue.toggle()
          curveLabel = "linear"
        }
      }
    }
    .padding(1)
  }
}
