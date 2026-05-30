@_spi(Runners) import SwiftTUI

/// Reproduces H2/H3 (the resolve hot path): a single narrow `@State` mutation in
/// a large, otherwise-static view tree.
///
/// State is localized to a small `CounterControl` child, so a click invalidates
/// only that child. The large static grid is a *sibling* of `CounterControl`
/// (not a descendant), so it is disjoint from the invalidation and is, in
/// principle, reuse-eligible. The diagnostic columns expose how much of the tree
/// actually recomputes per click: `resolved_computed` vs `resolved_reused`, and
/// whether `resolve_ms` scales with the grid size.
///
/// At the current pin the disjoint grid is **not** reused — `resolved_reused`
/// stays ~0 and the whole tree recomputes every invalidation frame — because the
/// per-frame transaction `debugSignature` (the run loop's frame-cause summary)
/// defeats `ViewNode.canReuse`'s retained-reuse check. Making that reuse fire is
/// an open optimization that also requires the reuse path to preserve focus and
/// active-animation state; see the H2/H3 findings report.
///
/// The static-grid row count is fixed by default (smoke-test friendly) but can be
/// overridden with `TERMUI_PERF_INVALIDATION_TREE_ROWS` to sweep tree sizes and
/// show whether `resolve_ms` scales with the grid.
public struct SyntheticNarrowInvalidationScenario: PerfScenario {
  public let name: PerfScenarioName = .syntheticNarrowInvalidation
  public let defaultTerminalSize = PerfTerminalSize(columns: 80, rows: 40)
  public let scriptedEvents = ["click inc; mutate one isolated @State leaf in a static tree"]
  public let visualMarkers = ["count 0"]
  public let settlingDescription = "first frame that shows count 0"

  private static let defaultRowCount = 6
  private static let columnCount = 4
  private static let clickCount = 8

  public init() {}

  @MainActor
  public func run(options: PerfScenarioRunOptions) async throws -> PerfScenarioRunResult {
    let rowCount = Self.resolvedRowCount()
    return try await PerfScenarioRunner.runWindow(
      scenario: self,
      options: options
    ) {
      PerfNarrowInvalidationProbeView(
        rowCount: rowCount,
        columnCount: Self.columnCount
      )
    } drive: { driver in
      _ = try await driver.waitForFrame(containing: "count 0")
      let dispatchTime = monotonicSeconds()
      var lastFrame = driver.terminalHost.presentedFrames.last?.frameNumber ?? 0
      for click in 1...Self.clickCount {
        let cell = try driver.cell(containing: "inc")
        driver.sendClick(at: cell)
        let matching = try await driver.waitForFrame(
          containing: "count \(click)",
          afterFrame: lastFrame
        )
        lastFrame = matching.frameNumber
      }
      let settled = driver.terminalHost.presentedFrames.last
      return [
        PerfEventRecord(
          eventID: "synthetic-narrow-invalidation",
          eventType: "mouse_click",
          dispatchTimeSeconds: dispatchTime,
          expectedVisualMarker: "count \(Self.clickCount)",
          firstMatchingFrame: lastFrame,
          firstMatchingTimeSeconds: settled?.timestampSeconds ?? dispatchTime,
          finalSettledFrame: settled?.frameNumber ?? lastFrame,
          finalSettledTimeSeconds: settled?.timestampSeconds ?? dispatchTime
        )
      ]
    }
  }

  private static func resolvedRowCount() -> Int {
    guard let raw = environmentValue("TERMUI_PERF_INVALIDATION_TREE_ROWS"),
      let parsed = Int(raw),
      parsed > 0
    else {
      return defaultRowCount
    }
    return parsed
  }
}

private struct PerfNarrowInvalidationProbeView: View {
  let rowCount: Int
  let columnCount: Int

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      // State is localized to this small child, so a click invalidates ONLY the
      // CounterControl subtree — NOT the static grid sibling below it.
      CounterControl()
      // Large static grid, a SIBLING of CounterControl (not a descendant), so it
      // is disjoint from the invalidation and SHOULD be reusable across the
      // click frames rather than recomputed every frame.
      ForEach(Array(0..<rowCount), id: \.self) { row in
        HStack(spacing: 1) {
          ForEach(Array(0..<columnCount), id: \.self) { column in
            Text("r\(row)c\(column)").border(.separator)
          }
        }
      }
    }
    .padding(1)
  }
}

private struct CounterControl: View {
  @State private var counter = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("count \(counter)")
      Button("inc") {
        counter += 1
      }
    }
  }
}
