import Observation
package import SwiftTUIViews

/// The autonomous "Life-shaped" workload probe: a self-driving `.task` loop
/// that sleeps a fixed tick interval and writes an `@Observable` model read
/// only by a child label, mirroring the gallery Game-of-Life auto-tick (the
/// workload behind the 0.1.9 browser frame-coalescing incident and the
/// Life-tab starvation guards).
///
/// The writer/reader split is load-bearing: the tick write invalidates only
/// the label node, so the `.task`-hosting node is REUSED on tick frames and
/// the frame's registration draft records no task re-registration. That is
/// what makes a steady tick frame classify visual-only (droppable) — the
/// exact "per-tick emission under reuse" regime of the incident. Hosting the
/// tick `@State` on the task node itself re-records the task every frame and
/// the `.taskStart` blocker makes every frame must-commit, hiding the
/// disposal arm from tests.
///
/// Lives in Tests/Support because the tick's `Task.sleep` is the *workload
/// under test* — an autonomous producer, not a waiter (the same sanctioned
/// autonomous-workload-tick shape as the `TaskReadsUnbodiedStateTests` game
/// loop and the GeometryReader 20 ms probe). Tests that consume it must
/// synchronise on signals (`RecordingPresentationSurface.frameSignal`,
/// `RunLoopProgressProbe` events), never on the tick interval itself.
package struct PerTickAutonomousProbeView: View {
  @State private var model: PerTickProbeModel

  /// Bounded so a leaked workload cannot tick forever, but sized to outlast
  /// the cadence suite's 5-minute test time limit: the tick lifetime is
  /// consumed from *task start*, and the tests need the workload alive
  /// through ~14 frame latencies (the held raster entry plus eight
  /// post-release presents). The amd64 CI lane proved multi-second frame
  /// latencies twice — 256 ticks (1.28 s) and 4096 ticks (20 s) both
  /// exhausted before the held entry was reached — so no "reasonable"
  /// budget is safe; only outlasting the time limit is
  /// (65536 × 5 ms ≈ 328 s > 300 s). Tests stop the tick via
  /// ``PerTickProbeModel/stopped`` before requesting exit, so real exits
  /// drain immediately; the budget only bounds the leak after a test
  /// failure abandons the run loop.
  package static let tickLimit = 65536

  package init(model: PerTickProbeModel = PerTickProbeModel()) {
    _model = State(initialValue: model)
  }

  package var body: some View {
    VStack(alignment: .leading) {
      PerTickProbeLabel(model: model)
      PerTickTaskHost(model: model)
    }
  }
}

/// Hoisted so the owning test can stop the workload (`stopped = true`)
/// before requesting exit; nothing in any body reads `stopped`, so setting
/// it mints no invalidation.
@Observable
package final class PerTickProbeModel {
  package var tick = 0
  package var stopped = false

  package init() {}
}

private struct PerTickProbeLabel: View {
  let model: PerTickProbeModel

  var body: some View {
    Text("tick \(model.tick)")
  }
}

/// The `.task`-hosting sibling. `Equatable` by model identity so the reuse
/// gate skips its re-resolve on tick frames — if it re-resolved, the task
/// registration would re-record into every frame's draft and the
/// `.taskStart` drop blocker would make every tick frame must-commit (see
/// the type-level doc).
private struct PerTickTaskHost: View, @MainActor Equatable {
  let model: PerTickProbeModel

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.model === rhs.model
  }

  var body: some View {
    Text("")
      .task { [model] in
        while !Task.isCancelled && !model.stopped
          && model.tick < PerTickAutonomousProbeView.tickLimit
        {
          try? await Task.sleep(nanoseconds: 5_000_000)
          model.tick += 1
        }
      }
  }
}
