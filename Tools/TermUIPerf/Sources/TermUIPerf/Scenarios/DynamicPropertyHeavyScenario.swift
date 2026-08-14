@_spi(Runners) import SwiftTUI

/// Preview-readiness Stage-0 control for the cost of updating many dynamic
/// properties ahead of retained reuse.
///
/// Each of 64 stable row nodes owns three third-party `DynamicProperty`
/// wrappers, each composed from `@State`. A key command invalidates only the
/// phase marker above the grid; unlike a pointer click it does not add a broad
/// focus/press suppression cone. Reached rows therefore run their
/// dynamic-property update passes and certify `.unchanged`; the graph census
/// and reuse-denial census record whether the current runtime can retain them
/// or instead walks the full reached tree. This is deliberately different from
/// a large state-free tree: it prices the public authoring contract selected in
/// Stage 1.
public struct DynamicPropertyHeavyScenario: PerfScenario {
  public let name: PerfScenarioName = .dynamicPropertyHeavy
  public let defaultTerminalSize = PerfTerminalSize(columns: 100, rows: 40)
  public let scriptedEvents = [
    "send ctrl-a eight times above 64 rows with three composed dynamic properties each"
  ]
  public let visualMarkers = ["dynamic phase 0"]
  public let settlingDescription = "first frame that shows dynamic phase 0"

  private static let rowCount = 64
  private static let clickCount = 8

  public init() {}

  @MainActor
  public func run(options: PerfScenarioRunOptions) async throws -> PerfScenarioRunResult {
    try await PerfScenarioRunner.runWindow(
      scenario: self,
      options: options
    ) {
      PerfDynamicPropertyHeavyView(rowCount: Self.rowCount)
    } drive: { driver in
      _ = try await driver.waitForFrame(containing: "dynamic phase 0")
      let dispatchTime = monotonicSeconds()
      var lastFrame = driver.terminalHost.presentedFrames.last?.frameNumber ?? 0

      for phase in 1...Self.clickCount {
        driver.sendKey(KeyPress(.character("a"), modifiers: .ctrl))
        let advanced = try await driver.waitForFrame(
          containing: "dynamic phase \(phase)",
          afterFrame: lastFrame
        )
        lastFrame = advanced.frameNumber
      }

      let settled = driver.terminalHost.presentedFrames.last
      return [
        PerfEventRecord(
          eventID: "dynamic-property-heavy",
          eventType: "mouse_click",
          dispatchTimeSeconds: dispatchTime,
          expectedVisualMarker: "dynamic phase \(Self.clickCount)",
          firstMatchingFrame: lastFrame,
          firstMatchingTimeSeconds: settled?.timestampSeconds ?? dispatchTime,
          finalSettledFrame: settled?.frameNumber ?? lastFrame,
          finalSettledTimeSeconds: settled?.timestampSeconds ?? dispatchTime
        )
      ]
    }
  }
}

extension DynamicPropertyHeavyScenario: BenchColdRenderable {
  func makeColdRoot() -> PerfDynamicPropertyHeavyView {
    PerfDynamicPropertyHeavyView(rowCount: Self.rowCount)
  }
}

struct PerfDynamicPropertyHeavyView: View {
  let rowCount: Int

  @State private var phase = 0

  var body: some View {
    Panel(id: "perf-dynamic-property-heavy") {
      VStack(alignment: .leading, spacing: 0) {
        Text("dynamic phase \(phase)")
        Text("ctrl-a advances")
        ForEach(0..<rowCount, id: \.self) { row in
          PerfDynamicPropertyRow(index: row)
        }
      }
      .padding(1)
    }
    .keyCommand("Advance dynamic phase", key: .character("a"), modifiers: .ctrl) {
      phase += 1
    }
  }
}

private struct PerfDynamicPropertyRow: View {
  let index: Int

  @PerfCertifiedDynamicCount private var first: Int
  @PerfCertifiedDynamicCount private var second: Int
  @PerfCertifiedDynamicCount private var third: Int

  var body: some View {
    Text("dynamic row \(index): \(first + second + third)")
  }
}

/// Third-party-shaped composed wrapper. The nested `@State` owns storage; the
/// wrapper's explicit certification makes the retained-reuse result observable
/// in the scenario's `resolved_reused` census.
@propertyWrapper
@MainActor
private struct PerfCertifiedDynamicCount: DynamicProperty {
  @State private var count = 0

  init() {}

  func update(in context: DynamicPropertyContext) -> DynamicPropertyUpdateResult {
    .unchanged
  }

  var wrappedValue: Int {
    count
  }
}
