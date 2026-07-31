@_spi(Runners) import SwiftTUI

/// Program Stage 0, WP-2: the programmatic jump — the Class-B vehicle.
///
/// One `scrollTo` moves the window ~9,500 rows in a single frame, with no
/// intermediate offsets to amortise the work across. Where the notch and
/// cadence scenarios measure the cost of moving a viewport by one row many
/// times, this measures the cost of moving it a long way once: a different
/// shape of the same pipeline, and the one an anchor-driven jump (search
/// result, "go to line", focus reveal) actually produces.
public struct ScrollJumpScenario: PerfScenario {
  public let name: PerfScenarioName = .scrollJump
  public let defaultTerminalSize = PerfTerminalSize(columns: 80, rows: 32)
  public let scriptedEvents = [
    "one programmatic scrollTo from the top of a windowed collection to row ~9,500"
  ]
  public let visualMarkers = ["srow 0"]
  public let settlingDescription = "first frame showing the collection's first row"
  public let initialFrameTimeout: Duration = .seconds(60)

  public init() {}

  @MainActor
  public func run(options: PerfScenarioRunOptions) async throws -> PerfScenarioRunResult {
    let rowCount = ScrollScenarioContent.rowCount()
    // Land near the end without depending on how many rows the border and
    // clamping leave visible.
    let target = max(0, Int(Double(rowCount) * 0.95))
    return try await PerfScenarioRunner.runWindow(
      scenario: self,
      options: options
    ) {
      PerfScrollJumpView(rowCount: rowCount, target: target)
    } drive: { driver in
      _ = try await driver.waitForFrame(containing: "srow 0", timeout: .seconds(120))
      let lastFrame = driver.terminalHost.presentedFrames.last?.frameNumber ?? 0
      let jumpCell = try driver.cell(containing: "JUMP")

      let dispatch = monotonicSeconds()
      driver.sendClick(at: jumpCell)
      let settled = try await driver.waitForFrame(
        containing: "srow \(target)",
        afterFrame: lastFrame,
        timeout: .seconds(120)
      )

      return [
        PerfEventRecord(
          eventID: "scroll-jump",
          eventType: "scroll",
          dispatchTimeSeconds: dispatch,
          expectedVisualMarker: "srow \(target)",
          firstMatchingFrame: settled.frameNumber,
          firstMatchingTimeSeconds: settled.timestampSeconds,
          finalSettledFrame: settled.frameNumber,
          finalSettledTimeSeconds: settled.timestampSeconds
        )
      ]
    }
  }
}

private struct PerfScrollJumpView: View {
  let rowCount: Int
  let target: Int

  var body: some View {
    ScrollViewReader { proxy in
      VStack(alignment: .leading, spacing: 0) {
        Button("JUMP") {
          proxy.scrollTo(target)
        }
        List(0..<rowCount, id: \.self) { index in
          HStack(spacing: 1) {
            Text("srow \(index)")
            Spacer(minLength: 1)
            Text("meta \(index % 97)")
              .foregroundStyle(.separator)
          }
        }
        .frame(height: 24)
        .border(.separator)
      }
      .padding(1)
    }
  }
}
