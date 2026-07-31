@_spi(Runners) import SwiftTUI

/// B1 / item B (D71/S5) — the rich-text steady-state repaint A/B class the
/// pipeline/runtime paydown program specified and never built.
///
/// Delivery condition 4 of plan 2026-07-28-009 requires that rich-text layout
/// is served from `TextLayoutCache` in *both* the draw phase and the semantics
/// phase, such that "a steady-state frame re-rasterizing an unchanged rich
/// `Text` performs zero wraps". The cache-unit tests proved admission; nothing
/// measured the steady state.
///
/// Shape, per the plan: a rich `Text` containing links, with animated chrome
/// *elsewhere* forcing repaints, so the rich payload itself never changes
/// while frames keep being produced. Metric: raster + semantics phase time per
/// frame.
///
/// The load-bearing assertion is the wrap count, not the timing:
/// `TextLayoutCache.shared.metrics.misses` must not grow across the measured
/// steady-state window. A timing win with a growing miss count would mean the
/// saving came from somewhere else and the D71 claim is still unproven.
public struct SyntheticRichSteadyRepaintScenario: PerfScenario {
  public let name: PerfScenarioName = .syntheticRichSteadyRepaint
  public let defaultTerminalSize = PerfTerminalSize(columns: 80, rows: 24)
  public let scriptedEvents = [
    "capture first render of a link-bearing rich text block",
    "warm the rich key, then advance measured unchanged repaints",
  ]
  public let visualMarkers = ["rich steady pass 0"]
  public let settlingDescription = "first settled frame after the measured repaints"

  private static let repaintCount = 6

  public init() {}

  @MainActor
  public func run(options: PerfScenarioRunOptions) async throws -> PerfScenarioRunResult {
    try await PerfScenarioRunner.runWindow(
      scenario: self,
      options: options
    ) {
      PerfRichSteadyRepaintProbeView()
    } drive: { driver in
      let first = try await driver.waitForFrame(containing: "rich steady pass 0")
      var events = [
        PerfEventRecord(
          eventID: "rich-steady-first-render",
          eventType: "initial_frame",
          dispatchTimeSeconds: first.timestampSeconds,
          expectedVisualMarker: "rich steady pass 0",
          firstMatchingFrame: first.frameNumber,
          firstMatchingTimeSeconds: first.timestampSeconds,
          finalSettledFrame: first.frameNumber,
          finalSettledTimeSeconds: first.timestampSeconds
        )
      ]

      // Warm the rich key OUTSIDE the measured window. The process-wide cache
      // survives benchmark iterations and the admission gate deliberately
      // bypasses a full cache on first sighting, so an unwarmed first repaint
      // would measure a miss regime and understate the steady state. This is
      // the same precaution SyntheticMeshTextScenario documents.
      let repaintCell = try driver.cell(containing: "repaint chrome")
      driver.sendClick(at: repaintCell)
      var lastFrame = try await driver.waitForFrame(
        containing: "rich steady pass 1",
        afterFrame: first.frameNumber
      ).frameNumber

      for pass in 2...(Self.repaintCount + 1) {
        let dispatchTime = monotonicSeconds()
        driver.sendClick(at: repaintCell)
        let matching = try await driver.waitForFrame(
          containing: "rich steady pass \(pass)",
          afterFrame: lastFrame
        )
        lastFrame = matching.frameNumber
        events.append(
          PerfEventRecord(
            eventID: "rich-steady-repaint-\(pass)",
            eventType: "steady_repaint",
            dispatchTimeSeconds: dispatchTime,
            expectedVisualMarker: "rich steady pass \(pass)",
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
}

private struct PerfRichSteadyRepaintProbeView: View {
  @State private var pass = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("repaint chrome") {
        pass += 1
      }
      // Chrome that changes every pass, forcing a repaint...
      Text("rich steady pass \(pass)")
      // ...while the rich payload below stays byte-identical, so a correct
      // cache serves it with zero wraps on every frame after the first.
      Self.richBody
    }
  }

  /// Link-bearing rich text. Two things make this the right payload: mixed
  /// styled runs force the `.richText` draw path rather than plain `.text`,
  /// and links are the case that previously bypassed the layout cache in
  /// *both* the draw and the semantics phase — semantics extraction walks the
  /// link table, so a semantics-side miss would not show up in raster timing
  /// alone.
  ///
  /// Authored by `Text` interpolation rather than an attributed string:
  /// `SwiftTUIViews` is Foundation-free, so `AttributedString` is not
  /// available here. This is the idiom the surface tests use.
  private static var richBody: Text {
    Text(
      """
      Rich steady-state body with \(Text("inline emphasis").bold()) and \
      \(Text("styled fragments").italic()) that must be wrapped exactly once. \
      See \(Link("the reuse article", destination: "https://swifttui.sh/reuse")) \
      and \(Link("the oracle map", destination: "https://swifttui.sh/oracles")) \
      then continue reading so this block spans several wrapped rows rather \
      than a single line.
      """
    )
  }
}
