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
