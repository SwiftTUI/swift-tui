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
  @State private var model = PerTickProbeModel()

  /// Bounded so the workload goes quiet on its own: an unbounded
  /// self-invalidating tick starves the cooperative-exit drain under the
  /// `.async` disposal churn (measured ~26 s to honor ctrl-D in-process),
  /// the same shape as the logo-tab flush-before-exit incident. Sized so the
  /// budget (~1.3 s of ticking) comfortably outlasts the cadence tests'
  /// bounded held-tail window under parallel-suite load while keeping the
  /// exit drain short.
  package static let tickLimit = 256

  package init() {}

  package var body: some View {
    VStack(alignment: .leading) {
      PerTickProbeLabel(model: model)
      PerTickTaskHost(model: model)
    }
  }
}

@Observable
private final class PerTickProbeModel {
  var tick = 0
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
        while !Task.isCancelled && model.tick < PerTickAutonomousProbeView.tickLimit {
          try? await Task.sleep(nanoseconds: 5_000_000)
          model.tick += 1
        }
      }
  }
}
