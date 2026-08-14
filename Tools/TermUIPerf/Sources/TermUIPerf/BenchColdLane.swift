import Foundation
@_spi(Runners) import SwiftTUI
@_spi(Runners) import SwiftTUIRuntime

/// A suite member that can construct its root view fresh for the cold lane
/// (plan 2026-08-11-005 D3): construction + one composed `renderOneShot`
/// pass per iteration, no run loop, no scheduler.
///
/// The root must be PINNED — same shape every call, no environment reads —
/// because its counters feed a committed baseline. A warm scenario's
/// env-tunable knobs (row-count overrides, boundary A/B selectors)
/// deliberately do not apply here.
@MainActor
protocol BenchColdRenderable: PerfScenario {
  associatedtype ColdRoot: View
  func makeColdRoot() -> ColdRoot
}

/// The cold-lane result for one member (D3/D6).
public struct PerfBenchColdReport: Codable, Equatable, Sendable {
  public var iterations: Int
  /// Iteration 1's wall time — the true cold render, where per-type plan
  /// caches fill. Reported separately, never averaged in.
  public var firstRenderMs: Double
  /// Wall-time stats over iterations 4..N (iterations 2-3 are discarded as
  /// process warm-up).
  public var renderMs: PerfStat
  /// Per-phase wall-time stats over the same measured iterations.
  public var resolveMs: PerfStat
  public var measureMs: PerfStat
  public var placeMs: PerfStat
  public var drawMs: PerfStat
  public var rasterMs: PerfStat
  /// The counter set every iteration reproduced bit-identically — a run
  /// only produces this report if the identity check held for all N.
  public var counters: PerfDeterministicCounters

  public init(
    iterations: Int,
    firstRenderMs: Double,
    renderMs: PerfStat,
    resolveMs: PerfStat = PerfStat(values: []),
    measureMs: PerfStat = PerfStat(values: []),
    placeMs: PerfStat = PerfStat(values: []),
    drawMs: PerfStat = PerfStat(values: []),
    rasterMs: PerfStat = PerfStat(values: []),
    counters: PerfDeterministicCounters
  ) {
    self.iterations = iterations
    self.firstRenderMs = firstRenderMs
    self.renderMs = renderMs
    self.resolveMs = resolveMs
    self.measureMs = measureMs
    self.placeMs = placeMs
    self.drawMs = drawMs
    self.rasterMs = rasterMs
    self.counters = counters
  }

  private enum CodingKeys: String, CodingKey {
    case iterations
    case firstRenderMs = "first_render_ms"
    case renderMs = "render_ms"
    case resolveMs = "resolve_ms"
    case measureMs = "measure_ms"
    case placeMs = "place_ms"
    case drawMs = "draw_ms"
    case rasterMs = "raster_ms"
    case counters
  }
}

public enum BenchColdLaneError: Error, Equatable, CustomStringConvertible {
  /// The nondeterminism failure D3 mandates: a cold iteration produced a
  /// different work census than iteration 1 under identical inputs.
  case counterDrift(scenario: String, iteration: Int, drifted: [String])

  public var description: String {
    switch self {
    case .counterDrift(let scenario, let iteration, let drifted):
      return
        "cold lane nondeterminism in \(scenario): iteration \(iteration) drifted on "
        + "\(drifted.joined(separator: ", ")). Identical inputs must produce an "
        + "identical work census; investigate before trusting any baseline."
    }
  }
}

enum BenchColdLane {
  static let defaultIterations = PerfBenchConfig.defaultColdIterations
  /// Iterations 2-3 are discarded as process warm-up (D3); iteration 1 is
  /// `first_render_ms`.
  static let discardedWarmupIterations = 2

  @MainActor
  static func run(
    _ scenario: any BenchColdRenderable,
    iterations: Int = defaultIterations
  ) throws -> PerfBenchColdReport {
    try runOpened(scenario, iterations: iterations)
  }

  @MainActor
  private static func runOpened<S: BenchColdRenderable>(
    _ scenario: S,
    iterations: Int
  ) throws -> PerfBenchColdReport {
    let size = scenario.defaultTerminalSize
    let proposal = ProposedSize(width: size.columns, height: size.rows)

    var firstRenderMs = 0.0
    var renderTimes: [Double] = []
    var phaseTimes: [FramePhaseTimings] = []
    var canonical: PerfDeterministicCounters?
    for iteration in 1...iterations {
      // Fresh view AND fresh renderer/graph each iteration: the lane
      // measures construction + first layout + first raster, so nothing may
      // carry over except process-global per-type caches — which is exactly
      // what the iteration-1 split exists to expose.
      let root = scenario.makeColdRoot()
      let renderer = DefaultRenderer()
      let start = monotonicSeconds()
      let snapshot = renderer.render(root, proposal: proposal)
      let elapsedMs = (monotonicSeconds() - start) * 1000

      let counters = coldCounters(from: snapshot)
      if let canonical {
        guard counters == canonical else {
          throw BenchColdLaneError.counterDrift(
            scenario: scenario.name.rawValue,
            iteration: iteration,
            drifted: driftedCounterNames(canonical, counters)
          )
        }
      } else {
        canonical = counters
      }

      if iteration == 1 {
        firstRenderMs = elapsedMs
      } else if iteration > 1 + discardedWarmupIterations {
        renderTimes.append(elapsedMs)
        if let timings = snapshot.diagnostics.timing.phaseTimings {
          phaseTimes.append(timings)
        }
      }
    }

    return PerfBenchColdReport(
      iterations: iterations,
      firstRenderMs: firstRenderMs,
      renderMs: PerfStat(values: renderTimes),
      resolveMs: PerfStat(values: phaseTimes.map { ms($0.resolve) }),
      measureMs: PerfStat(values: phaseTimes.map { ms($0.measure) }),
      placeMs: PerfStat(values: phaseTimes.map { ms($0.place) }),
      drawMs: PerfStat(values: phaseTimes.map { ms($0.draw) }),
      rasterMs: PerfStat(values: phaseTimes.map { ms($0.raster) }),
      counters: canonical ?? PerfDeterministicCounters()
    )
  }

  /// The cold work census, read from the typed products the one-shot
  /// pipeline already returns — nothing is re-instrumented (plan mechanism
  /// point 2).
  @MainActor
  static func coldCounters(from snapshot: RenderSnapshot) -> PerfDeterministicCounters {
    let work = snapshot.diagnostics.work
    let counts = snapshot.diagnostics.counts
    let branching = work.layoutBranchingCounters
    let rasterImageAttachments = snapshot.rasterSurface.imageAttachments.count
    return PerfDeterministicCounters(
      committedFrames: 1,
      answeredInputs: 0,
      resolvedComputed: work.resolvedNodesComputed,
      resolvedReused: work.resolvedNodesReused,
      measuredComputed: work.measuredNodesComputed,
      drawNodes: counts.drawNodes,
      // Preserve absence for non-image scenarios. The still-image baseline's
      // value 1 becomes `stale` if image resolution ever silently disappears.
      rasterImageAttachments: rasterImageAttachments > 0 ? rasterImageAttachments : nil,
      presentCells: rasterizedCells(snapshot.rasterSurface),
      builtinContainerMeasures: branching.builtinContainerMeasures,
      builtinChildMeasureRequests: branching.builtinChildMeasureRequests,
      builtinChildMeasureRequestsProbe: branching.builtinChildMeasureRequestsProbe,
      customContainerMeasures: branching.customContainerMeasures,
      customChildMeasureRequests: branching.customChildMeasureRequests,
      customChildMeasureRequestsProbe: branching.customChildMeasureRequestsProbe,
      customPlacementChildMeasureRequests: branching.customPlacementChildMeasureRequests
    )
  }

  /// Non-empty cells the raster produced — the cold analog of the warm
  /// lane's presented-cell census (D4's "raster product").
  static func rasterizedCells(_ surface: RasterSurface) -> Int {
    surface.cells.reduce(0) { total, row in
      total + row.count { $0 != .empty }
    }
  }

  private static func driftedCounterNames(
    _ canonical: PerfDeterministicCounters,
    _ drifted: PerfDeterministicCounters
  ) -> [String] {
    let canonicalValues = canonical.valuesByName
    let driftedValues = drifted.valuesByName
    return Set(canonicalValues.keys)
      .union(driftedValues.keys)
      .filter { canonicalValues[$0] != driftedValues[$0] }
      .sorted()
      .map { name in
        let before = canonicalValues[name].map(String.init) ?? "-"
        let after = driftedValues[name].map(String.init) ?? "-"
        return "\(name) (\(before) -> \(after))"
      }
  }

  private static func ms(_ duration: Duration) -> Double {
    Double(duration.components.seconds) * 1000
      + Double(duration.components.attoseconds) / 1e15
  }
}
