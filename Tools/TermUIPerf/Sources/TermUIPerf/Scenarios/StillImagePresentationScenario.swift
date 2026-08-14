@_spi(Runners) import SwiftTUI

/// Preview-readiness Stage-0 control for resolving, laying out, and presenting
/// one non-trivial still image through the real `Image(data:)` path.
///
/// The scripted drive alternates attachment opacity without changing the image
/// bytes. This keeps decoding/presentation and attachment reuse visible while
/// avoiding animated-image scheduling and per-frame source churn.
public struct StillImagePresentationScenario: PerfScenario {
  public let name: PerfScenarioName = .stillImagePresentation
  public let defaultTerminalSize = PerfTerminalSize(columns: 80, rows: 28)
  public let scriptedEvents = ["toggle one still image's opacity eight times"]
  public let visualMarkers = ["still image phase 0"]
  public let settlingDescription = "first frame that shows still image phase 0"

  private static let clickCount = 8

  public init() {}

  @MainActor
  public func run(options: PerfScenarioRunOptions) async throws -> PerfScenarioRunResult {
    try await PerfScenarioRunner.runWindow(
      scenario: self,
      options: options
    ) {
      PerfStillImagePresentationView()
    } drive: { driver in
      _ = try await driver.waitForFrame(containing: "still image phase 0")
      let dispatchTime = monotonicSeconds()
      var lastFrame = driver.terminalHost.presentedFrames.last?.frameNumber ?? 0

      for phase in 1...Self.clickCount {
        let cell = try driver.cell(containing: "toggle image opacity")
        driver.sendClick(at: cell)
        let advanced = try await driver.waitForFrame(
          containing: "still image phase \(phase)",
          afterFrame: lastFrame
        )
        lastFrame = advanced.frameNumber
      }

      let settled = driver.terminalHost.presentedFrames.last
      return [
        PerfEventRecord(
          eventID: "still-image-presentation",
          eventType: "mouse_click",
          dispatchTimeSeconds: dispatchTime,
          expectedVisualMarker: "still image phase \(Self.clickCount)",
          firstMatchingFrame: lastFrame,
          firstMatchingTimeSeconds: settled?.timestampSeconds ?? dispatchTime,
          finalSettledFrame: settled?.frameNumber ?? lastFrame,
          finalSettledTimeSeconds: settled?.timestampSeconds ?? dispatchTime
        )
      ]
    }
  }
}

extension StillImagePresentationScenario: BenchColdRenderable {
  func makeColdRoot() -> PerfStillImagePresentationView {
    PerfStillImagePresentationView()
  }
}

struct PerfStillImagePresentationView: View {
  @State private var phase = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("still image phase \(phase)")
      Button("toggle image opacity") {
        phase += 1
      }
      Image(data: Self.imageBytes)
        .scaledToFit()
        .opacity(phase.isMultiple(of: 2) ? 1 : 0.45)
        .frame(width: 48, height: 16)
      Text("160x80 embedded RGBA gradient")
        .foregroundStyle(.muted)
    }
    .padding(1)
  }

  /// Encoded once per process so the scenario prices still-image resolution
  /// and presentation, not fixture construction.
  private static let imageBytes: [UInt8] = {
    let width = 160
    let height = 80
    var pixels: [AnimatedImagePixel] = []
    pixels.reserveCapacity(width * height)
    for y in 0..<height {
      for x in 0..<width {
        pixels.append(
          AnimatedImagePixel(
            red: UInt8((x * 3 + y) % 256),
            green: UInt8((x + y * 5) % 256),
            blue: UInt8((x * 7 + y * 3) % 256),
            alpha: UInt8((x / 16 + y / 10).isMultiple(of: 2) ? 255 : 176)
          )
        )
      }
    }
    return AnimatedImageFrame(width: width, height: height, pixels: pixels).imageData
  }()
}
