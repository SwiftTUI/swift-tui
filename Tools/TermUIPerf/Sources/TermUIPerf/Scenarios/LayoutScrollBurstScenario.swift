import Layouts
@_spi(Runners) import SwiftTUI

public struct LayoutScrollBurstScenario: PerfScenario {
  public let name: PerfScenarioName = .layoutScrollBurst
  public let defaultTerminalSize = PerfTerminalSize(columns: 90, rows: 28)
  public let scriptedEvents = ["scroll vertical layout viewport"]
  public let visualMarkers = ["row 3"]
  public let settlingDescription = "first frame whose scroll viewport shows row 3"

  public init() {}

  @MainActor
  public func run(options: PerfScenarioRunOptions) async throws -> PerfScenarioRunResult {
    try await PerfScenarioRunner.runWindow(
      scenario: self,
      options: options
    ) {
      VerticalScrollMeasuresContent()
    } drive: { driver in
      _ = try await driver.waitForFrame(containing: "row 0")
      let dispatchTime = monotonicSeconds()
      let frameBeforeScroll = driver.terminalHost.presentedFrames.last?.frameNumber ?? 0
      driver.sendScroll(deltaY: 3, at: CellPoint(x: 4, y: 4))
      let matchingFrame = try await driver.waitForFrame(
        containing: "row 3",
        afterFrame: frameBeforeScroll
      )
      return [
        PerfEventRecord(
          eventID: "layout-scroll-burst-1",
          eventType: "scroll",
          dispatchTimeSeconds: dispatchTime,
          expectedVisualMarker: "row 3",
          firstMatchingFrame: matchingFrame.frameNumber,
          firstMatchingTimeSeconds: matchingFrame.timestampSeconds,
          finalSettledFrame: matchingFrame.frameNumber,
          finalSettledTimeSeconds: matchingFrame.timestampSeconds
        )
      ]
    }
  }
}
