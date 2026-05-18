import SwiftTUICore
import SwiftTUIViews
import Testing

@_spi(Runners) @testable import SwiftTUIRuntime

/// Structural guards for the composed runtime render pipeline (F1, F12).
///
/// `RuntimeRenderPipeline` is a sequenced executor: each `render*` entry point
/// iterates `RuntimeRenderStageName.orderedComposition` and dispatches every
/// stage through an exhaustive `switch`. Stage order is therefore enforced by
/// the executor loop, not by prose or a `precondition`. These tests pin that
/// structural property and the wall-clock time cost of the composed path.
@MainActor
@Suite
struct RenderPipelineStructureTests {
  /// A 20-row VStack/ForEach view rendered into an 80×40 proposal — the frame
  /// shape used to measure the executor's per-frame cost.
  private struct BenchmarkView: View {
    var body: some View {
      VStack {
        ForEach(0..<20) { index in
          Text("row \(index)")
        }
      }
    }
  }

  /// Baseline wall-clock time for 1000 composed renders of `BenchmarkView`.
  ///
  /// Captured by running this test once before the Option B refactor (the
  /// sequenced-executor rewrite) with the constant at `.zero`, reading the
  /// printed elapsed time, and pinning it here. The assertion allows 2× the
  /// baseline so the executor rewrite cannot silently regress the hot path.
  ///
  /// Pre-refactor measurement: 1000 frames in ~4.45s in a debug build on the
  /// reference machine. Pinned at 4.5s to absorb run-to-run jitter.
  private static let renderTimeBaseline: Duration = .milliseconds(4500)

  /// Stage order is structural, not configurable.
  ///
  /// The executor reads `RuntimeRenderStageName.orderedComposition` and
  /// `RuntimeRenderPipeline` exposes no initializer parameter that could hold a
  /// different order — `RuntimeRenderPipeline()` is the only way to build one.
  /// There is therefore no run-time path by which the pipeline could execute
  /// stages in any sequence other than the canonical composition (F1).
  @Test("pipeline stage order is structural, not a configurable parameter")
  func stageOrderIsStructural() {
    let pipeline = RuntimeRenderPipeline()

    #expect(pipeline.stageOrder == RuntimeRenderStageName.orderedComposition)
    #expect(
      RuntimeRenderStageName.orderedComposition == [
        .head,
        .animationInjection,
        .latePreferenceReconciliation,
        .fusedFrameTail,
        .commit,
      ])
    // `RuntimeRenderPipeline` has a single, parameterless initializer: the only
    // expressible pipeline runs the canonical order. If a `stageOrder:` (or any
    // other) initializer parameter were re-introduced, this call site would
    // still compile, but the executor would no longer guarantee a fixed order —
    // see the design note in `RuntimeRenderPipeline`. The F1/F12
    // Definition-of-Done grep guard (`precondition(stageOrder` and
    // `RuntimeFrameHeadStage` must print nothing) backs this at source level.
    #expect(type(of: pipeline) == RuntimeRenderPipeline.self)
  }

  @Test("composed render path stays within 2x the pre-refactor time budget")
  func composedRenderTimeBudget() {
    let proposal = ProposedSize(width: .finite(80), height: .finite(40))
    let iterations = 1000

    // Warm caches so the measurement reflects steady-state cost.
    _ = DefaultRenderer().render(BenchmarkView(), proposal: proposal)

    let clock = ContinuousClock()
    let elapsed = clock.measure {
      for _ in 0..<iterations {
        _ = DefaultRenderer().render(BenchmarkView(), proposal: proposal)
      }
    }

    // This is a coarse blunder-detector: the 2× headroom over a
    // machine-specific wall-clock baseline catches only gross O(n) regressions,
    // not subtle ones. Do not tighten the multiplier — wall-clock on a
    // shared or CI machine would become flaky.
    print("composedRenderTimeBudget: \(iterations) frames in \(elapsed)")

    let budget = Self.renderTimeBaseline * 2
    #expect(
      elapsed <= budget,
      "composed render path took \(elapsed); budget is \(budget) (2x baseline)")
  }
}
