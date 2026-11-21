import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIGraph
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

// The run-loop probe of the review of transition stages 2, 3 and 4a
// (root repository, docs/reports/2026-11-21-transition-stages-review.md).
// It uses only API that exists at swift-tui 0.22.2, so the baseline suite
// beside it compiles there.

@MainActor
final class StagesReviewClock { var now = MonotonicInstant.now() }

@MainActor
final class StagesReviewLog {
  var step: Binding<Int>?
  var value: Binding<Double>?
  /// The names of the completions that fired, in order.
  var completions: [String] = []
  /// The data each evaluation of the shape under test ran with, in order.
  var values: [Double] = []
  /// The field outside the data that each of those evaluations ran with.
  var fields: [String] = []
}

/// A run-loop harness around a view that is a function of one integer and
/// one `Double` of state, driven on an injected frame clock. Nothing waits.
@MainActor
final class StagesReviewProbe<Content: View> {
  let harness: StressRuntimeHarness<StagesReviewProbeRoot<Content>>
  let clock: StagesReviewClock
  let log: StagesReviewLog

  init(
    named name: String,
    size: CellSize = .init(width: 30, height: 6),
    log: StagesReviewLog = StagesReviewLog(),
    @ViewBuilder content: @escaping (Int, Double, StagesReviewLog) -> Content
  ) throws {
    self.log = log
    harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("transition-stages-review", name),
      size: size
    ) {
      StagesReviewProbeRoot(log: log, content: content)
    }
    // The clock starts after the mount frame: a frame never runs earlier
    // than the frame before it.
    let clock = StagesReviewClock()
    self.clock = clock
    harness.runLoop.frameClock = { clock.now }
  }

  var controller: AnimationController {
    harness.runLoop.renderer.internalAnimationController
  }

  var frame: String { harness.frame }

  /// One row of the frame without its trailing spaces.
  func line(_ row: Int) -> String {
    let rows = frame.split(separator: "\n", omittingEmptySubsequences: false)
    guard rows.indices.contains(row) else { return "" }
    return String(rows[row].reversed().drop { $0 == " " }.reversed())
  }

  /// Property animations in flight.
  var activeAnimationCount: Int { controller.activeAnimationCount }

  /// Removal overlays in flight.
  var removingCount: Int { controller.debugStateSnapshot().removingNodeIDs.count }

  func shutdown() { harness.shutdown() }

  /// Runs `body` with the animation sinks bound, passing the start instant.
  func run(_ body: (MonotonicInstant) throws -> Void) throws {
    try withAnimationSinks(controller) { try body(clock.now) }
  }

  /// Writes the step and renders the frame of the change. `animation: nil`
  /// is a plain state write.
  func set(_ step: Int, animation: Animation?, completion name: String = "done") throws {
    let binding = try #require(log.step)
    let log = log
    if let animation {
      withAnimation(animation) {
        binding.wrappedValue = step
      } completion: {
        log.completions.append(name)
      }
    } else {
      binding.wrappedValue = step
    }
    _ = try harness.render()
  }

  /// Writes the value and renders the frame of the change.
  func setValue(_ value: Double, animation: Animation?, completion name: String = "value") throws {
    let binding = try #require(log.value)
    let log = log
    if let animation {
      withAnimation(animation) {
        binding.wrappedValue = value
      } completion: {
        log.completions.append(name)
      }
    } else {
      binding.wrappedValue = value
    }
    _ = try harness.render()
  }

  /// Renders every armed turn before `target`, then one frame exactly at it.
  func advance(to target: MonotonicInstant) throws {
    var turns = 0
    while let wake = harness.runLoop.scheduler.nextWakeInstant(after: clock.now), wake < target,
      turns < 1024
    {
      clock.now = wake
      _ = try harness.render()
      turns += 1
    }
    #expect(turns < 1024, "the scheduler must reach the target within the turn budget")
    clock.now = target
    harness.runLoop.scheduler.requestDeadline(clock.now)
    _ = try harness.render()
  }
}

struct StagesReviewProbeRoot<Content: View>: View {
  @State private var step = 0
  @State private var value = 0.0
  let log: StagesReviewLog
  let content: (Int, Double, StagesReviewLog) -> Content

  var body: some View {
    let _ = capture()
    content(step, value, log)
  }

  private func capture() {
    log.step = $step
    log.value = $value
  }
}

/// The rows of `view` rendered once, at rest, by a renderer of its own.
@MainActor
func stagesReviewRows<V: View>(_ name: String, _ view: V) -> [String] {
  DefaultRenderer().renderArtifacts(
    view,
    context: .init(identity: testIdentity("transition-stages-review", "rest", name)),
    proposal: ProposedSize(width: .finite(30), height: .finite(6))
  ).rasterSurface.lines
}
