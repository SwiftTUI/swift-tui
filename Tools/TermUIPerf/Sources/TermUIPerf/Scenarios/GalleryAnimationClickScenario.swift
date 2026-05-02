import GalleryDemoViews
@_spi(Runners) import TerminalUI

public struct GalleryAnimationClickScenario: PerfScenario {
  public let name: PerfScenarioName = .galleryAnimationClick
  public let defaultTerminalSize = PerfTerminalSize(columns: 110, rows: 38)
  public let scriptedEvents = ["click linear animation button"]
  public let visualMarkers = ["curve: linear"]
  public let settlingDescription = "first frame whose animation section reports curve: linear"

  public init() {}

  @MainActor
  public func run(options: PerfScenarioRunOptions) async throws -> PerfScenarioRunResult {
    try await withGalleryInitialTab("animations") {
      try await PerfScenarioRunner.runWindow(
        scenario: self,
        options: options
      ) {
        GalleryView()
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

  private func withGalleryInitialTab<T>(
    _ tab: String,
    operation: () async throws -> T
  ) async throws -> T {
    let key = "GALLERY_INITIAL_TAB"
    let oldValue = environmentValue(key)
    try setEnvironmentValue(tab, for: key)
    defer {
      try? setEnvironmentValue(oldValue, for: key)
    }
    return try await operation()
  }
}
