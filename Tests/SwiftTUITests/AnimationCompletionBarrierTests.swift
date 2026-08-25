import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIGraph
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// Completion barriers on the synchronous frame driver (plan 2026-08-25-002
/// T2/T3 pins, from the gallery rework's findings): a segmented picker under
/// a focus move or a press-and-drag must not trip the resolved-tree skip
/// oracle; a state write from a `.logicallyComplete` closure fired early by
/// `Animation.logicallyComplete(after:)` must not disturb the in-flight
/// springs; and a removal transition's `.removed` barrier must fire on the
/// controller's own armed turns.
@MainActor
@Suite(.serialized)
struct AnimationCompletionBarrierTests {
  @Test("a Tab focus move onto a segmented picker does not trip the skip oracle")
  func segmentedPickerFocusMoveSurvivesSkipOracle() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("PickerFocusProbeRoot"),
      size: .init(width: 60, height: 8)
    ) {
      PickerFocusProbeFixture()
    }
    defer { harness.shutdown() }
    _ = try harness.pressKey(KeyPress(.tab))
    _ = try harness.renderAfterExternalMutation()
    _ = try harness.pressKey(KeyPress(.tab))
    _ = try harness.renderAfterExternalMutation()
    #expect(harness.frame.contains("Alpha"))
  }

  @Test("a press-and-drag across a segmented picker does not trip the skip oracle")
  func segmentedPickerDragSurvivesSkipOracle() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("PickerDragProbeRoot"),
      size: .init(width: 60, height: 8)
    ) {
      PickerFocusProbeFixture()
    }
    defer { harness.shutdown() }
    let start = MonotonicInstant.now()
    var now = start
    harness.runLoop.frameClock = { now }
    let body = try #require(harness.point(forText: "body"))
    let alpha = try #require(harness.point(forText: "Alpha"))
    for origin in [body, alpha] {
      _ = try harness.sendMouse(.down(.primary), at: origin)
      for step in 1...4 {
        now = now.advanced(by: .milliseconds(40))
        _ = try harness.sendMouse(
          .dragged(.primary), at: Point(x: origin.x + Double(step), y: origin.y))
      }
      _ = try harness.sendMouse(.up(.primary), at: Point(x: origin.x + 4, y: origin.y))
      _ = try harness.renderAfterExternalMutation()
    }
    #expect(harness.frame.contains("Alpha"))
  }

  @Test("a state write from an early logical completion keeps the spring in flight")
  func earlyLogicalCompletionWriteKeepsSpringInFlight() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("LogicalWriteProbeRoot"),
      size: .init(width: 60, height: 8)
    ) {
      LogicalCompletionWriteFixture()
    }
    defer { harness.shutdown() }
    let controller = harness.runLoop.renderer.internalAnimationController
    let clock = DeadlineDrivenFrameClock(harness: harness)

    try withAnimationSinks(controller) {
      try harness.clickText("go")
      _ = try harness.renderAfterExternalMutation()
    }
    #expect(controller.activeAnimationCount == 2, "the width + color springs are in flight")

    // Past the logical instant (500 ms) but well before the 1.5 s spring
    // settles: the closure fires at commit and its write lands on the next
    // frame.
    try withAnimationSinks(controller) {
      try clock.advance(by: .milliseconds(700))
    }
    #expect(harness.frame.contains("logical=1 removed=0"), "frame:\n\(harness.frame)")
    #expect(
      controller.activeAnimationCount == 2,
      "the springs must keep running after the early completion's state write; frame:\n\(harness.frame)"
    )
    try withAnimationSinks(controller) {
      try clock.advance(by: .milliseconds(200))
    }
    #expect(controller.activeAnimationCount == 2, "frame:\n\(harness.frame)")
    #expect(harness.frame.contains("logical=1 removed=0"), "frame:\n\(harness.frame)")

    try withAnimationSinks(controller) {
      try clock.advance(by: .seconds(6))
    }
    #expect(controller.activeAnimationCount == 0)
    #expect(harness.frame.contains("logical=1 removed=1"), "frame:\n\(harness.frame)")
  }

  @Test(
    "a removal transition's .removed completion schedules its own firing turn",
    arguments: [false, true])
  func removalTransitionRemovedCompletionSchedulesItsTurn(hostedInOverlay: Bool) throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("RemovalCompletionProbeRoot"),
      size: .init(width: 60, height: 8)
    ) {
      RemovalCompletionFixture(hostedInOverlay: hostedInOverlay)
    }
    defer { harness.shutdown() }
    let controller = harness.runLoop.renderer.internalAnimationController
    let clock = DeadlineDrivenFrameClock(harness: harness)
    #expect(harness.frame.contains("gone"))

    try withAnimationSinks(controller) {
      try harness.clickText("hide")
      _ = try harness.renderAfterExternalMutation()
    }
    #expect(harness.frame.contains("removed=0"), "frame:\n\(harness.frame)")

    // Render every armed turn through the 300 ms curve and the one-turn
    // final-visual hold: the head tick after the hold purges the overlay and
    // fires `.removed` before the loop goes idle.
    try withAnimationSinks(controller) {
      try clock.advance(by: .seconds(2))
    }
    #expect(
      harness.frame.contains("removed=1"),
      "the loop went idle (no armed turn) before .removed fired; frame:\n\(harness.frame)"
    )
    #expect(!harness.frame.contains("gone"))
  }
}

/// Drives the harness through every deadline the controller arms: the frame
/// instant is the armed deadline, so wall time only advances one frame per
/// render and a probe must render each turn to reach a later instant.
@MainActor
private final class DeadlineDrivenFrameClock<Content: View> {
  private let harness: StressRuntimeHarness<Content>
  private(set) var now = MonotonicInstant.now()

  init(harness: StressRuntimeHarness<Content>) {
    self.harness = harness
    harness.runLoop.frameClock = { [self] in now }
  }

  /// Advances the clock to `now + duration`, rendering every turn armed on
  /// the way; stops early once no turn is pending.
  func advance(by duration: Duration, maxTurns: Int = 2_000) throws {
    let target = now.advanced(by: duration)
    var turns = 0
    while turns < maxTurns {
      let scheduler = harness.runLoop.scheduler
      guard let wake = scheduler.nextWakeInstant(after: now), wake <= target else { break }
      now = wake
      _ = try harness.render()
      turns += 1
    }
    now = target
  }
}

@MainActor
private struct RemovalCompletionFixture: View {
  let hostedInOverlay: Bool
  @State private var shown = true
  @State private var removed = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("hide") {
        withAnimation(.linear(duration: .milliseconds(300)), completionCriteria: .removed) {
          shown = false
        } completion: {
          removed += 1
        }
      }
      if hostedInOverlay {
        Text("host").overlay(alignment: .leading) {
          if shown {
            Text("gone").transition(.opacity)
          }
        }
      } else if shown {
        Text("gone").transition(.opacity)
      }
      Text("removed=\(removed)")
    }
  }
}

@MainActor
private struct PickerFocusProbeFixture: View {
  @State private var page = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Picker("Page", selection: $page) {
        Text("Alpha").tag(0)
        Text("Beta").tag(1)
      }
      .pickerStyle(.segmented)
      Button("go") {}
      Text("body \(page)")
    }
  }
}

@MainActor
private struct LogicalCompletionWriteFixture: View {
  @State private var wide = false
  @State private var logical = 0
  @State private var removed = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("go") {
        var transaction = Transaction(
          animation: .spring(duration: .milliseconds(1_500), bounce: 0.4)
            .logicallyComplete(after: .milliseconds(500))
        )
        transaction.addAnimationCompletion(criteria: .logicallyComplete) { logical += 1 }
        transaction.addAnimationCompletion(criteria: .removed) { removed += 1 }
        withTransaction(transaction) { wide.toggle() }
      }
      .focusSection()
      Text(String(repeating: "█", count: 40))
        .foregroundStyle(wide ? Color.cyan : Color.yellow)
        .frame(maxWidth: .finite(wide ? 40 : 10), alignment: .leading)
      Text("logical=\(logical) removed=\(removed) wide=\(wide)")
    }
  }
}
