@_spi(Runners) import SwiftTUI

/// Reproduces P1 (the retained phase-product whole-tree gate): a single narrow
/// `@State` mutation in a large, otherwise-static tree that **also contains a
/// `Canvas`**.
///
/// A `Canvas` lowers to a `.canvas` draw payload, which does not support retained
/// phase extraction. Before the P1 fix a single such node anywhere in the
/// committed tree made `RetainedPhaseExtractionSignature.make` return nil, so
/// `storeCommittedFrame` discarded the **whole** frame's retained draw/semantic
/// products. The large static grid — a sibling of the counter, disjoint from the
/// narrow invalidation and otherwise reuse-eligible — was therefore re-extracted
/// (draw + semantics) from scratch on every click frame, purely because a Canvas
/// existed elsewhere in the tree. After P1 the products are retained with a nil
/// whole-tree signature, so the per-subtree partial-reuse path reuses the static
/// grid while only the (unsupported) Canvas re-extracts.
///
/// This is the canvas analogue of ``SyntheticNarrowInvalidationScenario``: the
/// click invalidates only the `CounterControl`, so the grid and Canvas are both
/// disjoint from the invalidation. The grid row count is overridable with
/// `TERMUI_PERF_CANVAS_REUSE_TREE_ROWS` to sweep tree sizes and show the saved
/// draw/semantic extraction scaling with the reusable subtree size.
public struct CanvasPartialReuseScenario: PerfScenario {
  public let name: PerfScenarioName = .canvasPartialReuse
  public let defaultTerminalSize = PerfTerminalSize(columns: 80, rows: 40)
  public let scriptedEvents = [
    "click inc; narrow @State mutation beside a Canvas and a large static grid"
  ]
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
      PerfCanvasReuseProbeView(
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
          eventID: "canvas-partial-reuse",
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
    guard let raw = environmentValue("TERMUI_PERF_CANVAS_REUSE_TREE_ROWS"),
      let parsed = Int(raw),
      parsed > 0
    else {
      return defaultRowCount
    }
    return parsed
  }
}

private struct PerfCanvasReuseProbeView: View {
  let rowCount: Int
  let columnCount: Int

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      // State is localized here, so a click invalidates ONLY the CounterControl
      // subtree — not the Canvas or the static grid below it.
      CounterControl()
      // A static Canvas. Its only role is to put a `.canvas` (retained-extraction-
      // unsupported) node in the committed tree: before P1 that alone discarded
      // the whole frame's retained phase products, so the static grid below lost
      // its draw/semantic reuse even though it is disjoint from the invalidation.
      Canvas(PerfBarsDrawing())
        .frame(width: 24, height: 4)
        .border(.separator)
      // Large static grid, a SIBLING of CounterControl and the Canvas. Disjoint
      // from the invalidation, so its draw + semantic extraction should be reused
      // across the click frames rather than re-extracted because a Canvas exists.
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

/// A small static value-type bar chart, just enough to make the Canvas a real
/// `.canvas` draw payload. Its `Equatable` conformance is structural, so the
/// drawing dedups across re-renders.
private struct PerfBarsDrawing: CanvasDrawing, Equatable {
  func draw(into context: inout CanvasContext) {
    let heights = [3.0, 6.0, 2.0, 7.0, 4.0, 5.0]
    let width = Double(context.size.width)
    let height = Double(context.size.height)
    guard width > 0, height > 0 else {
      return
    }
    let barWidth = max(1.0, width / Double(heights.count))
    for (index, value) in heights.enumerated() {
      let x = Double(index) * barWidth
      let barHeight = min(height, value)
      context.fillRect(
        Rect(
          origin: Point(x: x, y: height - barHeight),
          size: Size(width: max(0.5, barWidth - 0.5), height: barHeight)
        )
      )
    }
  }
}
