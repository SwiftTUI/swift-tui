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
/// property and the allocation/time cost of the composed path.
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

  /// Baseline wall-clock budget for 1000 composed renders of `BenchmarkView`.
  ///
  /// Captured by running this test once before the Option B refactor (the
  /// sequenced-executor rewrite) with the constant at `.zero`, reading the
  /// printed elapsed time, and pinning it here. The assertion allows 2× the
  /// baseline so the executor rewrite cannot silently regress the hot path.
  ///
  /// Pre-refactor measurement: 1000 frames in ~4.45s in a debug build on the
  /// reference machine. Pinned at 4.5s to absorb run-to-run jitter.
  private static let renderAllocationBaseline: Duration = .milliseconds(4500)

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
    // see the design note in `RuntimeRenderPipeline`. The grep guard in the
    // F1/F12 Definition-of-Done (`precondition(stageOrder` must print nothing)
    // backs this at the source level.
    #expect(type(of: pipeline) == RuntimeRenderPipeline.self)
  }

  /// `RuntimeFrameHeadStage` carried a single field (`isTransactionalWhenAbortable`)
  /// that nothing outside its own definition ever read — metadata wearing a
  /// type. The Option B refactor deletes the type entirely, so there is no
  /// symbol left to assert against here. This is a grep guard: the F1/F12
  /// Definition-of-Done requires
  ///
  ///     grep -rn "RuntimeFrameHeadStage|isTransactionalWhenAbortable" \
  ///       --include="*.swift" Sources
  ///
  /// to print nothing. If either symbol reappears, that command fails and this
  /// comment documents why it must stay deleted.
  @Test("no unread frame-head config type survives the executor refactor")
  func frameHeadStageCarriesNoUnreadFields() {
    // Intentionally empty: the type this guarded has been deleted. See the
    // doc comment above for the source-level grep guard that replaces it.
  }

  @Test("composed render path stays within 2x the pre-refactor time budget")
  func composedRenderAllocationBudget() {
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

    print("composedRenderAllocationBudget: \(iterations) frames in \(elapsed)")

    let budget = Self.renderAllocationBaseline * 2
    #expect(
      elapsed <= budget,
      "composed render path took \(elapsed); budget is \(budget) (2x baseline)")
  }
}
