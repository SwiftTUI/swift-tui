@_spi(Runners) import SwiftTUI

/// B1 / item B (D71) — the long-document `lineLimit` A/B class the
/// pipeline/runtime paydown program specified and never built.
///
/// Delivery condition 3 of plan 2026-07-28-009 requires that
/// `layoutText`/`layoutRichText` with `lineLimit: n` never wrap more than
/// `n + 1` rows of output, *including inside a single oversized logical line*,
/// "proven by the long-document lineLimit A/B class". The fixture suites
/// proved the boundary; nothing measured it. This is that measurement.
///
/// Shape, per the plan: a list of N rows, each a `Text` bound to a large
/// (multi-KB) string with `.lineLimit(1)`, **distinct content per row** so the
/// layout cache cannot serve them and the wrap cost itself is what is timed.
/// Metric: measure/layout phase time for the first frame and after a
/// width-changing resize.
///
/// Expectation being tested (the plan's *inferred* claim, now falsifiable):
/// wrap cost is independent of string length beyond the limit. The
/// `SWIFTTUI_PERF_LINE_LIMIT_BODY_SCALE` override exists so a sweep can show
/// that directly — doubling the body length should not move the measured
/// phase times.
public struct SyntheticLineLimitPreviewScenario: PerfScenario {
  public let name: PerfScenarioName = .syntheticLineLimitPreview
  public let defaultTerminalSize = PerfTerminalSize(columns: 80, rows: 40)
  public let scriptedEvents = [
    "capture first render of N lineLimit(1) rows over multi-KB bodies",
    "re-flow every row through a width change",
  ]
  public let visualMarkers = ["line limit preview pass 0"]
  public let settlingDescription = "first settled frame after the width change"

  private static let defaultRowCount = 24
  private static let defaultBodyScale = 1

  public init() {}

  @MainActor
  public func run(options: PerfScenarioRunOptions) async throws -> PerfScenarioRunResult {
    let rowCount = Self.resolvedRowCount()
    let bodyScale = Self.resolvedBodyScale()
    return try await PerfScenarioRunner.runWindow(
      scenario: self,
      options: options
    ) {
      PerfLineLimitPreviewProbeView(
        rowCount: rowCount,
        bodyScale: bodyScale
      )
    } drive: { driver in
      let first = try await driver.waitForFrame(containing: "line limit preview pass 0")
      var events = [
        PerfEventRecord(
          eventID: "line-limit-first-render",
          eventType: "initial_frame",
          dispatchTimeSeconds: first.timestampSeconds,
          expectedVisualMarker: "line limit preview pass 0",
          firstMatchingFrame: first.frameNumber,
          firstMatchingTimeSeconds: first.timestampSeconds,
          finalSettledFrame: first.frameNumber,
          finalSettledTimeSeconds: first.timestampSeconds
        )
      ]

      // A width change invalidates every row's wrap, so this is the leg that
      // isolates wrap cost from first-render setup. Under a correct
      // lineLimit budget it must not scale with body length.
      var lastFrame = first.frameNumber
      let reflowCell = try driver.cell(containing: "reflow line limit")
      for pass in 1...4 {
        let dispatchTime = monotonicSeconds()
        driver.sendClick(at: reflowCell)
        let matching = try await driver.waitForFrame(
          containing: "line limit preview pass \(pass)",
          afterFrame: lastFrame
        )
        lastFrame = matching.frameNumber
        events.append(
          PerfEventRecord(
            eventID: "line-limit-reflow-\(pass)",
            eventType: "width_reflow",
            dispatchTimeSeconds: dispatchTime,
            expectedVisualMarker: "line limit preview pass \(pass)",
            firstMatchingFrame: matching.frameNumber,
            firstMatchingTimeSeconds: matching.timestampSeconds,
            finalSettledFrame: matching.frameNumber,
            finalSettledTimeSeconds: matching.timestampSeconds
          )
        )
      }
      return events
    }
  }

  private static func resolvedRowCount() -> Int {
    guard let raw = environmentValue("SWIFTTUI_PERF_LINE_LIMIT_ROWS"),
      let value = Int(raw),
      value > 0
    else {
      return defaultRowCount
    }
    return value
  }

  private static func resolvedBodyScale() -> Int {
    guard let raw = environmentValue("SWIFTTUI_PERF_LINE_LIMIT_BODY_SCALE"),
      let value = Int(raw),
      value > 0
    else {
      return defaultBodyScale
    }
    return value
  }
}

private struct PerfLineLimitPreviewProbeView: View {
  let rowCount: Int
  let bodyScale: Int

  @State private var pass = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("reflow line limit") {
        pass += 1
      }
      Text("line limit preview pass \(pass)")
      ForEach(0..<rowCount, id: \.self) { row in
        // Distinct content per row defeats the layout cache, so each row pays
        // a real wrap. The `pass` in the body also defeats it across reflows.
        Text(Self.body(row: row, pass: pass, scale: bodyScale))
          .lineLimit(1)
          .frame(width: width)
      }
    }
  }

  /// Alternating widths so every reflow genuinely re-wraps rather than hitting
  /// a width the rows were already laid out against.
  private var width: Int {
    pass.isMultiple(of: 2) ? 60 : 44
  }

  private static func body(row: Int, pass: Int, scale: Int) -> String {
    // ~2 KB per row at scale 1, distinct per (row, pass).
    let unit = "row \(row) pass \(pass) lorem ipsum dolor sit amet consectetur "
    return String(repeating: unit, count: 40 * scale)
  }
}
