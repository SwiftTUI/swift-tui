@_spi(Runners) import SwiftTUI

/// Reproduces F153 (per-tick animated-image encode churn): an `AnimatedImage`
/// looping a synthetic multi-frame sequence re-encodes the current frame's
/// PNG bytes inside `body` on every tick, then re-hashes those bytes for the
/// image-repository lookup on every resolve.
///
/// Diagnostic columns to read for the playback window:
///   - `resolve_ms` / total CPU — encode + lookup-hash cost dominates here.
///   - committed frames — playback cadence sanity (one commit per tick).
public struct GifPlaybackScenario: PerfScenario {
  public let name: PerfScenarioName = .gifPlayback
  public let defaultTerminalSize = PerfTerminalSize(columns: 90, rows: 24)
  public let scriptedEvents = ["observe animated image playback ticks"]
  public let visualMarkers = ["gif playback"]
  public let settlingDescription = "first frame that contains the playback marker"

  public init() {}

  @MainActor
  public func run(options: PerfScenarioRunOptions) async throws -> PerfScenarioRunResult {
    try await PerfScenarioRunner.runWindow(
      scenario: self,
      options: options
    ) {
      PerfGifPlaybackProbeView()
    } drive: { driver in
      let frame = try await driver.waitForFrame(containing: "gif playback")
      let dispatchTime = monotonicSeconds()
      try? await Task.sleep(for: .seconds(3))
      return [
        PerfEventRecord(
          eventID: "gif-playback-settled",
          eventType: "idle",
          dispatchTimeSeconds: dispatchTime,
          expectedVisualMarker: "gif playback",
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

private struct PerfGifPlaybackProbeView: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("gif playback")
      AnimatedImage(Self.sequence)
    }
    .padding(1)
  }

  /// A 24-frame 96×48 sequence at 30 fps. Frames carry a per-frame shifting
  /// gradient so PNG filtering/deflate does representative work (uniform
  /// frames would compress trivially and understate the encode cost).
  private static let sequence: AnimatedImageSequence = {
    let width = 96
    let height = 48
    let frames = (0..<24).map { frameOrdinal in
      var pixels: [AnimatedImagePixel] = []
      pixels.reserveCapacity(width * height)
      for y in 0..<height {
        for x in 0..<width {
          let phase = (x + y + frameOrdinal * 7) % 256
          pixels.append(
            AnimatedImagePixel(
              red: UInt8(phase),
              green: UInt8((phase &* 3) % 256),
              blue: UInt8((phase &* 5) % 256),
              alpha: 255
            )
          )
        }
      }
      return AnimatedImageFrame(width: width, height: height, pixels: pixels)
    }
    return AnimatedImageSequence(frames: frames, framesPerSecond: 30)
  }()
}
