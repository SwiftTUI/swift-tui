@_spi(Runners) import SwiftTUI

/// Program Stage 0, WP-2: the heterogeneous-document shape — the mrkdwn
/// silhouette, and the scenario that pinned the windowing-eligibility cliff
/// Stage 2 removed (plan 2026-07-31-002).
///
/// The default block count sits **under** the frame-head worker-snapshot
/// budget (`4 * max(columns, rows)`) on purpose: under the budget the runtime
/// pre-realizes every block on the main actor so the frame tail can offload,
/// and the resulting snapshot reports `canRunOnWorker == true` — which the
/// pre-Stage-2 windowed measurement refused, so a *small* document was
/// measured exhaustively every frame while a *large* one was windowed. Both
/// sides of the budget now window; the default keeps this scenario on the
/// snapshot-source path (the real-document regime), and raising
/// `SWIFTTUI_PERF_SCROLL_DOCUMENT_BLOCKS` above the budget still flips it
/// onto the live-source path as a consistency lever.
///
/// Both drive shapes run here, back to back, because a document's cost is not
/// the same question closed-loop and open-loop: closed-loop shows the
/// per-notch price a user pays when the runtime keeps up, open-loop shows what
/// the same document does to a runtime that cannot.
public struct ScrollDocumentMixedScenario: PerfScenario {
  public let name: PerfScenarioName = .scrollDocumentMixed
  public let defaultTerminalSize = PerfTerminalSize(columns: 80, rows: 32)
  public let scriptedEvents = [
    "60 closed-loop wheel notches over a heterogeneous document, then one"
      + " 60 Hz open-loop burst"
  ]
  public let visualMarkers = ["sblk 0"]
  public let settlingDescription = "first frame showing the document's first block"
  public let initialFrameTimeout: Duration = .seconds(60)

  private static let closedLoopNotches = 60
  private static let openLoopNotches = 60

  public init() {}

  @MainActor
  public func run(options: PerfScenarioRunOptions) async throws -> PerfScenarioRunResult {
    let blockCount = ScrollScenarioContent.documentBlockCount()
    let closedLoopNotches = min(Self.closedLoopNotches, max(1, blockCount / 2))
    let openLoopNotches = min(Self.openLoopNotches, max(1, blockCount / 2))
    return try await PerfScenarioRunner.runWindow(
      scenario: self,
      options: options
    ) {
      PerfScrollDocumentView(blockCount: blockCount)
    } drive: { driver in
      _ = try await driver.waitForFrame(containing: "sblk 0", timeout: .seconds(120))
      let scrollCell = try driver.cell(containing: "sblk 0")
      var lastFrame = driver.terminalHost.presentedFrames.last?.frameNumber ?? 0
      var events: [PerfEventRecord] = []

      for notch in 0..<closedLoopNotches {
        let dispatch = monotonicSeconds()
        let settled = try await driver.scrollAwaitingFrame(
          deltaY: 1,
          at: scrollCell,
          afterFrame: lastFrame,
          timeout: .seconds(30)
        )
        lastFrame = settled.frameNumber
        events.append(
          PerfEventRecord(
            eventID: "scroll-document-notch-\(notch)",
            eventType: "scroll",
            dispatchTimeSeconds: dispatch,
            expectedVisualMarker: "<next presented frame>",
            firstMatchingFrame: settled.frameNumber,
            firstMatchingTimeSeconds: settled.timestampSeconds,
            finalSettledFrame: settled.frameNumber,
            finalSettledTimeSeconds: settled.timestampSeconds
          )
        )
      }

      let burstDispatch = monotonicSeconds()
      await driver.driveScroll(
        cadence: .microseconds(16_600),
        notches: openLoopNotches,
        at: scrollCell,
        deltaY: -1
      )
      await driver.waitForQuiescence(idle: .milliseconds(400), timeout: .seconds(60))
      let burstSettled = driver.terminalHost.presentedFrames.last
      events.append(
        PerfEventRecord(
          eventID: "scroll-document-cadence-burst",
          eventType: "scroll",
          dispatchTimeSeconds: burstDispatch,
          expectedVisualMarker: "<open-loop burst; see runtime latency columns>",
          firstMatchingFrame: burstSettled?.frameNumber,
          firstMatchingTimeSeconds: burstSettled?.timestampSeconds,
          finalSettledFrame: burstSettled?.frameNumber,
          finalSettledTimeSeconds: burstSettled?.timestampSeconds
        )
      )
      return events
    }
  }
}
