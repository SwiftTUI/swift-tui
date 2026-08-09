@_spi(Runners) import SwiftTUI

/// Scroll-latency R4-C: the heterogeneous document behind real-app chrome —
/// the silhouette the 2026-08-01 app-tier stage found missing (finding 4).
///
/// `scroll-document-mixed` models `ScrollView { LazyVStack { ForEach } }`
/// bare, which never runs an enclosing stack's ideal pass over the scroll
/// pane. Real apps wrap the pane in header/status chrome (`VStack { header;
/// Divider; HStack { … } }`) with a `maxHeight: .infinity` flexible frame —
/// the v5 bisection shape whose ideal round realized the entire document
/// every notch and held ~2.9 s of real-app latency. This scenario is that
/// shape, driven closed-loop like the mixed document, so the chrome cost is
/// measured framework-side.
public struct ScrollDocumentChromeScenario: PerfScenario {
  public let name: PerfScenarioName = .scrollDocumentChrome
  public let defaultTerminalSize = PerfTerminalSize(columns: 120, rows: 40)
  public let scriptedEvents = [
    "60 closed-loop wheel notches over a chrome-wrapped heterogeneous document"
  ]
  public let visualMarkers = ["sblk 0"]
  public let settlingDescription = "first frame showing the document's first block"
  public let initialFrameTimeout: Duration = .seconds(60)

  private static let closedLoopNotches = 60

  public init() {}

  @MainActor
  public func run(options: PerfScenarioRunOptions) async throws -> PerfScenarioRunResult {
    let blockCount = ScrollScenarioContent.documentBlockCount(default: 300)
    let closedLoopNotches = min(Self.closedLoopNotches, max(1, blockCount / 2))
    return try await PerfScenarioRunner.runWindow(
      scenario: self,
      options: options
    ) {
      PerfScrollChromeDocumentView(blockCount: blockCount)
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
            eventID: "scroll-chrome-notch-\(notch)",
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
      return events
    }
  }
}

/// The v5 chrome shape hosting the mixed-document content: header + divider
/// chrome stack, an HStack gutter, a `ScrollViewReader`, and the flexible
/// `maxHeight: .infinity` pane frame that defeats windowing without the R4-C
/// ideal estimate.
struct PerfScrollChromeDocumentView: View {
  let blockCount: Int

  var body: some View {
    VStack(spacing: 0) {
      Text("Scroll chrome workload")
        .foregroundStyle(.tint)
      Divider()
      HStack(alignment: .top, spacing: 2) {
        Spacer(minLength: 0)
        ScrollViewReader { _ in
          ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) {
              ForEach(0..<blockCount, id: \.self) { index in
                PerfScrollDocumentView(blockCount: blockCount).block(index)
              }
            }
          }
          .frame(maxWidth: .finite(118), maxHeight: .infinity, alignment: .topLeading)
        }
      }
    }
  }
}
