import Observation
import SwiftTUIRuntime
@_spi(Testing) import SwiftTUITestSupport
import Testing

/// `RunLoopTestHarness` (STUI-1571), used the way a package outside swift-tui
/// uses it: through `@_spi(Testing) import SwiftTUITestSupport` and public
/// API alone. Nothing here is `@testable`, and no assertion reads the run
/// loop, the scheduler, the animation controller or a registry.
///
/// Every test compares what the harness presented with a closed form. No
/// test sleeps or polls: time is the harness's virtual clock, and the three
/// tests that wait for a task or a release wait on an event it fires.
@MainActor
@Suite("Run-loop test harness", .serialized)
struct RunLoopTestHarnessTests {
  private static let gaugeSize = CellSize(width: 24, height: 3)
  private static let startKey = KeyPress(.character("g"))
  private static let toggleKey = KeyPress(.character("t"))

  // MARK: - The first frame

  @Test("init renders the first frame on a surface of the given size, at instant zero")
  func firstFrame() throws {
    let size = CellSize(width: 12, height: 3)
    let harness = try RunLoopTestHarness(size: size) {
      Text("first").frame(width: 12, height: 3, alignment: .topLeading)
    }
    defer { harness.shutdown() }

    #expect(harness.frameCount == 1)
    #expect(harness.frame.size == size)
    // One string for each row of the surface.
    #expect(harness.lines.count == 3)
    #expect(harness.lines == harness.frame.lines)
    #expect((0..<3).map { harnessRow(harness, $0) } == ["first", "", ""])
    #expect(harness.now == .zero)

    // Nothing is armed: the clock moves and no frame is presented.
    #expect(harness.nextWake == nil)
    #expect(try harness.advanceToNextWake() == false)
    #expect(harness.now == .zero)
    #expect(try harness.advance(by: .seconds(1)) == 0)
    #expect(harness.now == MonotonicInstant(offset: .seconds(1)))
    #expect(harness.frameCount == 1)

    // Pointer motion over a view that does not track it needs no frame.
    try harness.send(MouseEvent(kind: .moved, location: Point(x: 2, y: 0)))
    #expect(harness.frameCount == 1)
  }

  @Test("a surface with no cells is refused")
  func emptySurfaceThrows() throws {
    #expect(throws: (any Error).self) {
      try RunLoopTestHarness(size: CellSize(width: 0, height: 4)) { Text("none") }
    }
    let harness = try RunLoopTestHarness(size: CellSize(width: 8, height: 2)) { Text("some") }
    defer { harness.shutdown() }
    #expect(throws: (any Error).self) {
      try harness.resize(to: CellSize(width: 8, height: 0))
    }
    #expect(harness.frame.size == CellSize(width: 8, height: 2))
  }

  // MARK: - Virtual time

  @Test("advanceToNextWake yields each frame of a linear animation, at elapsed / 800")
  func linearAnimationFrameByFrame() throws {
    let log = HarnessLog()
    let harness = try RunLoopTestHarness(size: Self.gaugeSize) { HarnessGaugeScene(log: log) }
    defer { harness.shutdown() }
    #expect(harnessRow(harness, 1) == HarnessGauge.text(0))
    #expect(harness.nextWake == nil)

    // The key handler starts an 800 ms linear animation with a completion.
    try harness.press(Self.startKey)
    let start = harness.now
    // A key press does not move the clock.
    #expect(start == .zero)
    // The frame of the key press is the animation's first frame: the value
    // is still at its origin.
    #expect(log.values.last == 0)
    #expect(harnessRow(harness, 1) == HarnessGauge.text(0))
    #expect(log.completions == 0)

    // Each deadline shows `elapsed / 800`, and the completion fires once, on
    // the frame that reaches the target.
    try Self.expectLinearRun(of: harness, log, from: start, completions: 1)

    // The animation armed nothing after its last frame.
    let presented = harness.frameCount
    #expect(try harness.advanceToNextWake() == false)
    #expect(harness.frameCount == presented)
    #expect(harness.now == start.advanced(by: .milliseconds(825)))
    #expect(log.completions == 1)
  }

  @Test("advance(by:) presents the frames that single steps present, and ends in the same frame")
  func advanceMatchesSingleSteps() throws {
    let steppedLog = HarnessLog()
    let advancedLog = HarnessLog()
    let stepped = try RunLoopTestHarness(size: Self.gaugeSize) {
      HarnessGaugeScene(log: steppedLog)
    }
    defer { stepped.shutdown() }
    let advanced = try RunLoopTestHarness(size: Self.gaugeSize) {
      HarnessGaugeScene(log: advancedLog)
    }
    defer { advanced.shutdown() }
    try stepped.press(Self.startKey)
    try advanced.press(Self.startKey)
    #expect(advanced.frameCount == stepped.frameCount)

    let presentedBefore = stepped.frameCount
    var steps = 0
    while try stepped.advanceToNextWake() {
      steps += 1
      try #require(steps <= 64, "the animation must end")
    }
    #expect(steps == 25)
    let presentedByStepping = stepped.frameCount - presentedBefore
    #expect(presentedByStepping == 25)

    // The whole animation in one call: the same number of frames, the same
    // samples in the same order, the same last frame, the same instant.
    let presented = try advanced.advance(by: .milliseconds(825))
    #expect(presented == presentedByStepping)
    #expect(advanced.frameCount == stepped.frameCount)
    #expect(advancedLog.values == steppedLog.values)
    #expect(advanced.frame == stepped.frame)
    #expect(advanced.lines == stepped.lines)
    #expect(advanced.now == stepped.now)
    #expect(advanced.nextWake == nil)
    #expect(advancedLog.completions == 1)
  }

  @Test("advance(by:) renders each deadline at its own instant and leaves the clock at the end")
  func advanceIntervalEdges() throws {
    let log = HarnessLog()
    let harness = try RunLoopTestHarness(size: Self.gaugeSize) { HarnessGaugeScene(log: log) }
    defer { harness.shutdown() }
    try harness.press(Self.startKey)
    let start = harness.now
    func instant(_ milliseconds: Int) -> MonotonicInstant {
      start.advanced(by: .milliseconds(milliseconds))
    }
    #expect(harness.nextWake == instant(33))

    // The interval ends before the first deadline: only the clock moves.
    #expect(try harness.advance(by: .milliseconds(32)) == 0)
    #expect(harness.now == instant(32))
    #expect(harness.nextWake == instant(33))
    #expect(harnessRow(harness, 1) == HarnessGauge.text(0))

    // A deadline exactly at the end of the interval is inside it.
    #expect(try harness.advance(by: .milliseconds(1)) == 1)
    #expect(harness.now == instant(33))
    #expect(harnessRow(harness, 1) == HarnessGauge.text(33.0 / 800))

    // Three deadlines inside 100 ms. Each frame ran at its deadline, not at
    // the end of the interval, and the clock then stands at the end.
    let evaluations = log.values.count
    #expect(try harness.advance(by: .milliseconds(100)) == 3)
    #expect(harness.now == instant(133))
    let samples = Array(log.values[evaluations...])
    #expect(samples.count == 3, "\(samples)")
    for (sample, milliseconds) in zip(samples, [66.0, 99, 132]) {
      #expect(abs(sample - milliseconds / 800) < 1e-9, "\(samples)")
    }
    #expect(harnessRow(harness, 1) == HarnessGauge.text(132.0 / 800))
    #expect(harness.nextWake == instant(165))

    // An interval past the end of the animation renders what is left of it:
    // the deadlines from 165 ms to 825 ms.
    #expect(try harness.advance(by: .seconds(2)) == 21)
    #expect(harness.now == instant(2133))
    #expect(harnessRow(harness, 1) == HarnessGauge.text(1))
    #expect(log.completions == 1)
    #expect(harness.nextWake == nil)

    // With nothing armed only the clock moves, and it cannot move back.
    let presented = harness.frameCount
    #expect(try harness.advance(by: .seconds(1)) == 0)
    #expect(harness.now == instant(3133))
    #expect(throws: (any Error).self) {
      try harness.advance(by: .milliseconds(-1))
    }
    #expect(harness.now == instant(3133))
    #expect(harness.frameCount == presented)
  }

  // MARK: - Input

  @Test("press delivers a key to the focused view and renders the state it flips")
  func pressFlipsState() throws {
    let harness = try RunLoopTestHarness(size: CellSize(width: 20, height: 2)) {
      HarnessSwitchScene()
    }
    defer { harness.shutdown() }
    #expect(harnessRow(harness, 0) == "switch off")

    var presented = harness.frameCount
    try harness.press(KeyPress(.character("s")))
    #expect(harnessRow(harness, 0) == "switch on")
    #expect(harness.frameCount == presented + 1)

    presented = harness.frameCount
    try harness.press(KeyPress(.character("s")))
    #expect(harnessRow(harness, 0) == "switch off")
    #expect(harness.frameCount == presented + 1)

    // A key no view handles still gets the frame an input gets.
    presented = harness.frameCount
    try harness.press(KeyPress(.character("x")))
    #expect(harnessRow(harness, 0) == "switch off")
    #expect(harness.frameCount == presented + 1)

    // No input moved the clock or armed a deadline.
    #expect(harness.now == .zero)
    #expect(harness.nextWake == nil)
  }

  @Test("send delivers a click to a button and renders the state it changes")
  func sendClicksAButton() throws {
    let harness = try RunLoopTestHarness(size: CellSize(width: 20, height: 6)) {
      HarnessCounterScene()
    }
    defer { harness.shutdown() }
    #expect(harness.lines.contains { $0.contains("count 0") }, "\(harness.lines)")

    try Self.click("Add", in: harness)
    #expect(harness.lines.contains { $0.contains("count 1") }, "\(harness.lines)")
    try Self.click("Add", in: harness)
    #expect(harness.lines.contains { $0.contains("count 2") }, "\(harness.lines)")

    // A press that is released somewhere else activates nothing.
    let cell = try #require(harnessCell(of: "Add", in: harness))
    try harness.send(MouseEvent(kind: .down(.primary), location: Point(cell)))
    try harness.send(MouseEvent(kind: .up(.primary), location: Point(x: 19, y: 5)))
    #expect(harness.lines.contains { $0.contains("count 2") }, "\(harness.lines)")
    #expect(harness.now == .zero)
  }

  @Test("send stamps the event with the virtual instant, so a long press ends in virtual time")
  func sendFollowsTheVirtualClock() throws {
    let log = HarnessLog()
    let harness = try RunLoopTestHarness(size: CellSize(width: 20, height: 3)) {
      HarnessHoldScene(log: log)
    }
    defer { harness.shutdown() }
    let cell = try #require(harnessCell(of: "Hold", in: harness), "\(harness.lines)")

    // The event's own timestamp is the wall clock's. The harness replaces it
    // with its instant, so the recognizer's timer is armed 500 ms from now.
    try harness.send(MouseEvent(kind: .down(.primary), location: Point(cell)))
    #expect(log.count == 0)
    #expect(harness.nextWake == harness.now.advanced(by: .milliseconds(500)))

    try harness.advance(by: .milliseconds(499))
    #expect(log.count == 0)
    #expect(try harness.advance(by: .milliseconds(1)) >= 1)
    #expect(log.count == 1)
    #expect(harness.now == MonotonicInstant(offset: .milliseconds(500)))
  }

  @Test("paste reaches the focused field, and so does a key")
  func pasteReachesTheFocusedField() throws {
    let harness = try RunLoopTestHarness(size: CellSize(width: 30, height: 8)) {
      HarnessFieldScene()
    }
    defer { harness.shutdown() }
    #expect(harness.lines.contains { $0.contains("typed::") }, "\(harness.lines)")

    try harness.paste("hello")
    #expect(harness.lines.contains { $0.contains("typed:hello:") }, "\(harness.lines)")
    try harness.press(KeyPress(.character("!")))
    #expect(harness.lines.contains { $0.contains("typed:hello!:") }, "\(harness.lines)")
    #expect(harness.now == .zero)
  }

  @Test("resize changes the size of the presented surface and lays the scene out again")
  func resizeChangesTheSurface() throws {
    let harness = try RunLoopTestHarness(size: CellSize(width: 20, height: 4)) {
      Text(String(repeating: "x", count: 60))
    }
    defer { harness.shutdown() }
    #expect(harness.frame.size == CellSize(width: 20, height: 4))
    #expect(harness.lines.count == 4)
    #expect(harness.lines.map(\.count).max() == 20)

    let presented = harness.frameCount
    try harness.resize(to: CellSize(width: 30, height: 6))
    #expect(harness.frameCount == presented + 1)
    #expect(harness.frame.size == CellSize(width: 30, height: 6))
    #expect(harness.lines.count == 6)
    #expect(harness.lines.map(\.count).max() == 30)

    try harness.resize(to: CellSize(width: 10, height: 2))
    #expect(harness.frame.size == CellSize(width: 10, height: 2))
    #expect(harness.lines.count == 2)
    #expect(harness.lines.map(\.count).max() == 10)
    #expect(harness.now == .zero)
  }

  // MARK: - A change made outside the run loop

  @Test("render() shows a change made through a binding the test holds")
  func renderShowsABindingChange() throws {
    let log = HarnessLog()
    let harness = try RunLoopTestHarness(size: CellSize(width: 30, height: 2)) {
      HarnessNumberScene(log: log)
    }
    defer { harness.shutdown() }
    #expect(harnessRow(harness, 0) == "number 0 plain 0")
    let number = try #require(log.number)

    // The write asks for a frame. Nothing is presented until the test
    // renders: the last frame is the old one, and a frame is due now.
    number.wrappedValue = 7
    let presented = harness.frameCount
    #expect(harnessRow(harness, 0) == "number 0 plain 0")
    #expect(harness.nextWake == harness.now)
    try harness.render()
    #expect(harnessRow(harness, 0) == "number 7 plain 0")
    #expect(harness.frameCount == presented + 1)
    #expect(harness.nextWake == nil)

    // A change the view graph cannot observe asks for nothing. render()
    // invalidates the root, so the frame shows it.
    log.plain = 3
    #expect(harness.nextWake == nil)
    try harness.render()
    #expect(harnessRow(harness, 0) == "number 7 plain 3")
    #expect(harness.frameCount == presented + 2)

    // With nothing changed render() still presents a frame: the same one.
    let frame = harness.frame
    try harness.render()
    #expect(harness.frameCount == presented + 3)
    #expect(harness.frame == frame)
    #expect(harness.now == .zero)
  }

  @Test("render() shows a change to an observable model a view reads")
  func renderShowsAnObservableChange() throws {
    let model = HarnessModel()
    let harness = try RunLoopTestHarness(size: CellSize(width: 20, height: 2)) {
      HarnessModelScene(model: model)
    }
    defer { harness.shutdown() }
    #expect(harnessRow(harness, 0) == "model 0")

    model.count = 5
    // The view read the model, so the change asked for a frame.
    #expect(harness.nextWake == harness.now)
    #expect(harnessRow(harness, 0) == "model 0")
    let presented = harness.frameCount
    try harness.render()
    #expect(harnessRow(harness, 0) == "model 5")
    #expect(harness.frameCount == presented + 1)
  }

  @Test("a withAnimation in the test body animates a binding change that render() draws")
  func renderDrawsAnAnimatedBindingChange() throws {
    let log = HarnessLog()
    let harness = try RunLoopTestHarness(size: Self.gaugeSize) { HarnessGaugeScene(log: log) }
    defer { harness.shutdown() }
    let level = try #require(log.level)

    // The animation scope is the test's, outside any call of the harness.
    // The write carries the animation, and render() draws its first frame.
    try harness.advance(by: .seconds(3))
    withAnimation(HarnessTiming.linear) {
      level.wrappedValue = 1
    }
    #expect(harness.nextWake == harness.now)
    try harness.render()
    let start = harness.now
    #expect(start == MonotonicInstant(offset: .seconds(3)))
    #expect(log.values.last == 0)
    #expect(harnessRow(harness, 1) == HarnessGauge.text(0))

    // The frames follow the same line as an animation the scene starts.
    try Self.expectLinearRun(of: harness, log, from: start, completions: 0)
  }

  @Test("a withAnimation completion registered in the test body is not called")
  func completionRegisteredOutsideIsNotCalled() throws {
    let log = HarnessLog()
    let harness = try RunLoopTestHarness(size: Self.gaugeSize) { HarnessGaugeScene(log: log) }
    defer { harness.shutdown() }
    let level = try #require(log.level)

    // A documented limit. A completion is registered with the run loop that
    // is in scope, and in the test body, outside a call of the harness, none
    // is. The animation plays and the completion is dropped.
    withAnimation(HarnessTiming.linear) {
      level.wrappedValue = 1
    } completion: {
      log.completions += 1
    }
    try harness.render()
    try harness.advance(by: .seconds(2))
    #expect(log.values.last == 1)
    #expect(harnessRow(harness, 1) == HarnessGauge.text(1))
    #expect(harness.nextWake == nil)
    #expect(log.completions == 0)
  }

  @Test("the requestTermination action reports false, and the harness goes on")
  func requestTerminationIsRefused() throws {
    let log = HarnessLog()
    let harness = try RunLoopTestHarness(size: CellSize(width: 20, height: 2)) {
      HarnessTerminationScene(log: log)
    }
    defer { harness.shutdown() }

    // The harness is not a session that can end: the action has no session
    // to ask, and says so.
    try harness.press(KeyPress(.character("q")))
    #expect(log.answers == [false])
    // The exit key of a session, `Ctrl+C`, is a key like any other here.
    try harness.press(KeyPress(.character("c"), modifiers: .ctrl))
    #expect(log.keys == [KeyPress(.character("c"), modifiers: .ctrl)])
    let presented = harness.frameCount
    try harness.press(KeyPress(.character("q")))
    #expect(log.answers == [false, false])
    #expect(harness.frameCount == presented + 1)
  }

  @Test("the surface declines a link and has no clipboard, so a test starts no program")
  func hostActionsAreDeclined() throws {
    let log = HarnessLog()
    let harness = try RunLoopTestHarness(size: CellSize(width: 20, height: 2)) {
      HarnessHostActionsScene(log: log)
    }
    defer { harness.shutdown() }

    // The default open-link action hands the destination to the harness's
    // surface, which declines it. Were it the system's opener, it would
    // report that it started a program.
    try harness.press(KeyPress(.character("l")))
    #expect(log.answers == [false])
    // No clipboard takes the text.
    try harness.press(KeyPress(.character("w")))
    #expect(log.answers == [false, false])
  }

  // MARK: - Transitions

  @Test("an insertion and a removal through transition(_:) follow the animation's line")
  func transitionInsertionAndRemoval() throws {
    let log = HarnessLog()
    let harness = try RunLoopTestHarness(size: Self.gaugeSize) {
      HarnessTransitionScene(log: log)
    }
    defer { harness.shutdown() }
    #expect(harnessRow(harness, 1) == "")
    #expect(harness.nextWake == nil)

    // Insertion. The first frame that has the view shows the origin of the
    // transition, and each deadline shows `elapsed / 800`.
    try harness.press(Self.toggleKey)
    let inserted = harness.now
    try Self.expectShift(in: harness, log, at: 0, "insertion, 0 ms")
    for tick in 1...25 {
      #expect(try harness.advanceToNextWake(), "insertion, tick \(tick)")
      #expect(harness.now == inserted.advanced(by: .milliseconds(33 * tick)))
      try Self.expectShift(
        in: harness, log, at: min(1, Double(33 * tick) / 800), "insertion, tick \(tick)")
      #expect(log.completions == (tick == 25 ? 1 : 0), "insertion, tick \(tick)")
    }

    // The insertion has ended and a deadline is still armed, one frame
    // ahead: a view under a transition keeps the 33 ms frame deadline armed
    // for as long as it is present. That is a filed defect (STUI-1547:
    // `requiresContinuedAnimationFrames` stays true while a transition is
    // registered), pinned here as what the run loop does today. Those
    // frames draw the view at rest.
    #expect(harness.nextWake == harness.now.advanced(by: .milliseconds(33)))
    #expect(try harness.advanceToNextWake())
    try Self.expectShift(in: harness, log, at: 1, "at rest")

    // Removal, on a frame of that cadence. The first frame without the view
    // still draws all of it, and each deadline shows `1 - elapsed / 800`.
    try harness.press(Self.toggleKey)
    let removed = harness.now
    try Self.expectShift(in: harness, log, at: 1, "removal, 0 ms")
    for tick in 1...24 {
      #expect(try harness.advanceToNextWake(), "removal, tick \(tick)")
      #expect(harness.now == removed.advanced(by: .milliseconds(33 * tick)))
      try Self.expectShift(
        in: harness, log, at: 1 - Double(33 * tick) / 800, "removal, tick \(tick)")
      #expect(log.completions == 1, "removal, tick \(tick)")
    }
    // The removal ends on the first deadline past its 800 ms. That frame
    // draws nothing of the view, and the removal's completion fires on it.
    #expect(try harness.advanceToNextWake())
    #expect(harness.now == removed.advanced(by: .milliseconds(825)))
    #expect(harnessRow(harness, 1) == "")
    #expect(log.completions == 2)
    try Self.expectRest(harness)
  }

  @Test("a removal half way through an insertion continues from the value on screen")
  func removalInterruptsInsertion() throws {
    let log = HarnessLog()
    let harness = try RunLoopTestHarness(size: Self.gaugeSize) {
      HarnessTransitionScene(log: log)
    }
    defer { harness.shutdown() }

    try harness.press(Self.toggleKey)
    for tick in 1...13 {
      #expect(try harness.advanceToNextWake())
      try Self.expectShift(in: harness, log, at: Double(33 * tick) / 800, "insertion, tick \(tick)")
    }
    // 429 ms into the 800 ms insertion.
    let onScreen = 13 * 33.0 / 800

    // The frame of the removal shows the value that was on screen, through
    // the body the removal draws: nothing jumps to the identity value and
    // nothing restarts. The insertion's completion fires when it is
    // interrupted.
    try harness.press(Self.toggleKey)
    let removed = harness.now
    #expect(removed == MonotonicInstant(offset: .milliseconds(429)))
    try Self.expectShift(in: harness, log, at: onScreen, "removal, 0 ms")
    #expect(log.completions == 1)

    // The removal runs its own 800 ms from there, toward 0.
    for tick in 1...24 {
      #expect(try harness.advanceToNextWake(), "removal, tick \(tick)")
      #expect(harness.now == removed.advanced(by: .milliseconds(33 * tick)))
      try Self.expectShift(
        in: harness, log, at: onScreen * (1 - Double(33 * tick) / 800), "removal, tick \(tick)")
    }
    #expect(try harness.advanceToNextWake())
    #expect(harness.now == removed.advanced(by: .milliseconds(825)))
    #expect(harnessRow(harness, 1) == "")
    #expect(log.completions == 2)
    try Self.expectRest(harness)
  }

  @Test("an insertion half way through a removal continues from the value on screen")
  func insertionInterruptsRemoval() throws {
    let log = HarnessLog()
    let harness = try RunLoopTestHarness(size: Self.gaugeSize) {
      HarnessTransitionScene(log: log)
    }
    defer { harness.shutdown() }

    // The view arrives and comes to rest.
    try harness.press(Self.toggleKey)
    try harness.advance(by: .milliseconds(825))
    try Self.expectShift(in: harness, log, at: 1, "at rest")
    #expect(log.completions == 1)

    // It starts to leave, on a frame of the cadence its transition keeps
    // armed while it is present (STUI-1547).
    #expect(try harness.advanceToNextWake())
    try harness.press(Self.toggleKey)
    for tick in 1...13 {
      #expect(try harness.advanceToNextWake())
      try Self.expectShift(
        in: harness, log, at: 1 - Double(33 * tick) / 800, "removal, tick \(tick)")
    }
    let onScreen = 1 - 13 * 33.0 / 800

    // The view is live again, and its first frame shows what the removal
    // was showing. The removal's completion fires when it is interrupted.
    try harness.press(Self.toggleKey)
    let inserted = harness.now
    try Self.expectShift(in: harness, log, at: onScreen, "insertion, 0 ms")
    #expect(log.completions == 2)

    // The insertion runs its own 800 ms from there, toward 1.
    for tick in 1...25 {
      #expect(try harness.advanceToNextWake(), "insertion, tick \(tick)")
      #expect(harness.now == inserted.advanced(by: .milliseconds(33 * tick)))
      let progress = min(1, Double(33 * tick) / 800)
      try Self.expectShift(
        in: harness, log, at: onScreen + (1 - onScreen) * progress, "insertion, tick \(tick)")
      #expect(log.completions == (tick == 25 ? 3 : 2), "insertion, tick \(tick)")
    }
    #expect(harnessRow(harness, 1) == "PRESENT")
  }

  // MARK: - Isolation

  @Test("two harnesses at once keep their own clock, state and frames")
  func twoHarnessesAreIndependent() throws {
    let firstLog = HarnessLog()
    let secondLog = HarnessLog()
    let first = try RunLoopTestHarness(size: Self.gaugeSize) { HarnessGaugeScene(log: firstLog) }
    defer { first.shutdown() }
    let second = try RunLoopTestHarness(size: Self.gaugeSize) {
      HarnessGaugeScene(log: secondLog)
    }
    defer { second.shutdown() }
    let secondFrames = second.frameCount

    // The first animates. The second has no animation, no deadline and no
    // new frame, and its clock has not moved.
    try first.press(Self.startKey)
    try first.advance(by: .milliseconds(330))
    #expect(harnessRow(first, 1) == HarnessGauge.text(330.0 / 800))
    #expect(first.now == MonotonicInstant(offset: .milliseconds(330)))
    #expect(second.now == .zero)
    #expect(second.nextWake == nil)
    #expect(second.frameCount == secondFrames)
    #expect(harnessRow(second, 1) == HarnessGauge.text(0))
    #expect(secondLog.completions == 0)

    // The second starts later, on its own clock. The first does not move.
    let firstFrames = first.frameCount
    try second.advance(by: .seconds(5))
    try second.press(Self.startKey)
    try second.advance(by: .milliseconds(165))
    #expect(harnessRow(second, 1) == HarnessGauge.text(165.0 / 800))
    #expect(second.now == MonotonicInstant(offset: .milliseconds(5165)))
    #expect(first.now == MonotonicInstant(offset: .milliseconds(330)))
    #expect(first.frameCount == firstFrames)
    #expect(harnessRow(first, 1) == HarnessGauge.text(330.0 / 800))

    // Stepped in turn, each follows its own line.
    for tick in 1...5 {
      #expect(try first.advanceToNextWake())
      #expect(try second.advanceToNextWake())
      #expect(harnessRow(first, 1) == HarnessGauge.text(Double(330 + 33 * tick) / 800))
      #expect(harnessRow(second, 1) == HarnessGauge.text(Double(165 + 33 * tick) / 800))
    }

    // Each ends by itself, and each completion fires once, in its own scene.
    try first.advance(by: .seconds(1))
    #expect(firstLog.completions == 1)
    #expect(secondLog.completions == 0)
    #expect(first.nextWake == nil)
    #expect(second.nextWake != nil)
    try second.advance(by: .seconds(1))
    #expect(secondLog.completions == 1)
    #expect(harnessRow(first, 1) == HarnessGauge.text(1))
    #expect(harnessRow(second, 1) == HarnessGauge.text(1))
  }

  // MARK: - Calls the harness refuses

  @Test("a call made from a callback during another call throws, and the outer call finishes")
  func reentrantCallThrows() throws {
    let log = HarnessLog()
    let harness = try RunLoopTestHarness(size: CellSize(width: 20, height: 2)) {
      HarnessCallbackScene(log: log)
    }
    defer {
      log.action = nil
      harness.shutdown()
    }

    // The key handler runs inside press(_:). A call that renders from there
    // would start a frame inside a frame.
    log.action = {
      do {
        try harness.render()
      } catch {
        log.count += 1
      }
    }
    let presented = harness.frameCount
    try harness.press(KeyPress(.character("c")))
    #expect(log.count == 1)
    // The outer call rendered the frame of its key all the same.
    #expect(harness.frameCount == presented + 1)

    // The harness is as usable as before.
    log.action = nil
    try harness.press(KeyPress(.character("c")))
    #expect(log.count == 1)
    #expect(harness.frameCount == presented + 2)
  }

  @Test("a scene that changes its own state on every frame makes the call throw")
  func restlessSceneThrows() throws {
    let harness = try RunLoopTestHarness(size: CellSize(width: 20, height: 2)) {
      HarnessRestlessScene()
    }
    defer { harness.shutdown() }
    #expect(harnessRow(harness, 0) == "ticks 0")
    #expect(harness.nextWake == nil)

    // The key changes the state once. From then on every frame changes it
    // again, at the same instant, so no number of frames settles the scene.
    // The call renders 16 passes of the frame driver's 16 frames and throws.
    let presented = harness.frameCount
    #expect(throws: (any Error).self) {
      try harness.press(KeyPress(.character("r")))
    }
    #expect(harness.frameCount == presented + 256)
    #expect(harness.now == .zero)
    // A frame is still due.
    #expect(harness.nextWake == harness.now)
  }

  // MARK: - The end of a harness

  @Test("shutdown() can be called twice, and no frame is rendered after it")
  func shutdownTwice() throws {
    let log = HarnessLog()
    let harness = try RunLoopTestHarness(size: Self.gaugeSize) { HarnessGaugeScene(log: log) }
    try harness.press(Self.startKey)
    try harness.advance(by: .milliseconds(99))
    #expect(harness.nextWake != nil)
    let frame = harness.frame
    let presented = harness.frameCount
    let now = harness.now

    harness.shutdown()
    harness.shutdown()

    // What was presented stays readable, and nothing more is armed.
    #expect(harness.frame == frame)
    #expect(harness.lines == frame.lines)
    #expect(harness.frameCount == presented)
    #expect(harness.now == now)
    #expect(harness.nextWake == nil)

    // Every call that renders now throws, and renders nothing.
    #expect(throws: (any Error).self) { try harness.advanceToNextWake() }
    #expect(throws: (any Error).self) { try harness.advance(by: .milliseconds(33)) }
    #expect(throws: (any Error).self) { try harness.press(Self.startKey) }
    #expect(throws: (any Error).self) {
      try harness.send(MouseEvent(kind: .moved, location: Point(x: 0, y: 0)))
    }
    #expect(throws: (any Error).self) { try harness.paste("late") }
    #expect(throws: (any Error).self) { try harness.resize(to: CellSize(width: 30, height: 4)) }
    #expect(throws: (any Error).self) { try harness.render() }
    #expect(harness.frameCount == presented)
    #expect(harness.frame == frame)
    #expect(harness.now == now)
    // The animation that was in flight never reached its end.
    #expect(log.completions == 0)

    harness.shutdown()
  }

  @Test("shutdown() cancels the tasks the scene started", .timeLimit(.minutes(1)))
  func shutdownCancelsTasks() async throws {
    let started = AsyncEvent()
    let ended = AsyncEvent()
    let harness = try RunLoopTestHarness(size: CellSize(width: 10, height: 1)) {
      HarnessTaskScene(started: started, ended: ended)
    }
    // The task started with the first frame. Its body runs while the test
    // is suspended here, and then waits to be cancelled.
    await started.wait()
    harness.shutdown()
    // The body returns only when its task is cancelled.
    await ended.wait()
    harness.shutdown()
  }

  @Test("a harness released without shutdown() cancels the scene's tasks", .timeLimit(.minutes(1)))
  func releaseCancelsTasks() async throws {
    let started = AsyncEvent()
    let ended = AsyncEvent()
    var harness: RunLoopTestHarness<HarnessTaskScene>? = try RunLoopTestHarness(
      size: CellSize(width: 10, height: 1)
    ) {
      HarnessTaskScene(started: started, ended: ended)
    }
    await started.wait()
    #expect((harness?.frameCount ?? 0) >= 1)
    // No shutdown(): the last reference goes, and the run loop with it.
    harness = nil
    await ended.wait()
  }

  @Test("a harness released without shutdown() releases its scene", .timeLimit(.minutes(1)))
  func releaseFreesTheScene() async throws {
    let released = AsyncEvent()
    do {
      let log = HarnessLog()
      log.witness = HarnessWitness(released: released)
      let harness = try RunLoopTestHarness(size: Self.gaugeSize) { HarnessGaugeScene(log: log) }
      // Released in the middle of an animation, with a deadline armed and a
      // completion registered.
      try harness.press(Self.startKey)
      try harness.advance(by: .milliseconds(100))
      #expect(harness.nextWake != nil)
      #expect(log.completions == 0)
    }
    // The scene, its state and its completion closure held the only other
    // references to the log. With the harness gone the log goes, and its
    // witness with it. A leak would leave this waiting for the time limit.
    await released.wait()
  }

  // MARK: - Helpers

  /// Presses and releases the primary button on the middle of `text`.
  private static func click<Content: View>(
    _ text: String, in harness: RunLoopTestHarness<Content>
  ) throws {
    let cell = try #require(harnessCell(of: text, in: harness), "no \(text) in \(harness.lines)")
    let point = Point(CellPoint(x: cell.x + text.count / 2, y: cell.y))
    try harness.send(MouseEvent(kind: .down(.primary), location: point))
    try harness.send(MouseEvent(kind: .up(.primary), location: point))
  }

  /// Steps the 25 deadlines of the gauge's 800 ms linear animation, whose
  /// first frame was rendered at `start`, and compares each frame with
  /// `elapsed / 800`. `completions` is how many completions the animation
  /// has: they fire on the last frame and not before.
  private static func expectLinearRun<Content: View>(
    of harness: RunLoopTestHarness<Content>,
    _ log: HarnessLog,
    from start: MonotonicInstant,
    completions: Int
  ) throws {
    for tick in 1...25 {
      let presented = harness.frameCount
      #expect(try harness.advanceToNextWake(), "tick \(tick)")
      // One frame for each deadline, 33 ms after the one before.
      #expect(harness.frameCount == presented + 1, "tick \(tick)")
      #expect(harness.now == start.advanced(by: .milliseconds(33 * tick)), "tick \(tick)")
      // The last deadline is the first one past the 800 ms: the value is the
      // target there.
      let elapsed = harnessMilliseconds(start.duration(to: harness.now))
      let expected = min(1, elapsed / 800)
      let value = try #require(log.values.last)
      #expect(abs(value - expected) < 1e-9, "tick \(tick): \(value)")
      #expect(harnessRow(harness, 1) == HarnessGauge.text(expected), "tick \(tick)")
      #expect(log.completions == (tick == 25 ? completions : 0), "tick \(tick)")
    }
    #expect(log.values.last == 1)
    // The animation arms nothing after its last frame.
    #expect(harness.nextWake == nil)
  }

  /// The last frame evaluated `HarnessShift` with `expected`, and drew the
  /// view that many columns from its place.
  private static func expectShift<Content: View>(
    in harness: RunLoopTestHarness<Content>,
    _ log: HarnessLog,
    at expected: Double,
    _ label: String
  ) throws {
    let value = try #require(log.values.last, "\(label)")
    #expect(abs(value - expected) < 1e-9, "\(label): \(value), expected \(expected)")
    let drawn = String(repeating: " ", count: HarnessShift.indent(value)) + "PRESENT"
    #expect(harnessRow(harness, 1) == drawn, "\(label): \(harness.lines)")
  }

  /// After a removal has ended the run loop comes to rest. The frame that
  /// ends the removal still arms one deadline, 33 ms on. That frame draws
  /// nothing of the view and arms nothing, so stepping ends there.
  private static func expectRest<Content: View>(_ harness: RunLoopTestHarness<Content>) throws {
    let ended = harness.now
    #expect(harness.nextWake == ended.advanced(by: .milliseconds(33)))
    #expect(try harness.advanceToNextWake())
    #expect(harness.now == ended.advanced(by: .milliseconds(33)))
    #expect(harnessRow(harness, 1) == "", "\(harness.lines)")
    #expect(harness.nextWake == nil)
    #expect(try harness.advanceToNextWake() == false)
  }
}

// MARK: - Fixtures

/// What a test and its scene share.
@MainActor
private final class HarnessLog {
  /// The data each evaluation of the animated site ran with, in order.
  var values: [Double] = []
  var completions = 0
  var count = 0
  /// A value the view graph cannot observe: a plain property of a class.
  var plain = 0
  var number: Binding<Int>?
  var level: Binding<Double>?
  /// What the `c` key of `HarnessCallbackScene` runs.
  var action: (@MainActor () -> Void)?
  /// Released with the log.
  var witness: HarnessWitness?
  /// What an environment action answered, call by call.
  var answers: [Bool] = []
  /// The keys `HarnessTerminationScene` got other than `q`.
  var keys: [KeyPress] = []
}

/// Fires an event when it is released.
private final class HarnessWitness: Sendable {
  private let released: AsyncEvent

  init(released: AsyncEvent) {
    self.released = released
  }

  deinit {
    released.fire()
  }
}

@MainActor
private enum HarnessTiming {
  static let linear = Animation.linear(duration: .milliseconds(800))
}

/// A gauge whose level animates from 0 to 1 over 800 ms, with a completion,
/// when the focused view gets the `g` key.
private struct HarnessGaugeScene: View {
  @State private var level = 0.0
  let log: HarnessLog

  var body: some View {
    let _ = capture()
    VStack(alignment: .leading, spacing: 0) {
      Text("keys")
        .focusable()
        .onKeyPress(.character("g")) { _ in
          withAnimation(HarnessTiming.linear) {
            level = 1
          } completion: {
            log.completions += 1
          }
          return .handled
        }
      HarnessGauge(level: level, log: log)
    }
    .frame(width: 24, height: 3, alignment: .topLeading)
  }

  private func capture() {
    log.level = $level
  }
}

/// A view that conforms to `Animatable`: its body runs with the sample of
/// every frame, records it, and draws it as a number of hundred-thousandths.
private struct HarnessGauge: View, Animatable {
  var level: Double
  let log: HarnessLog

  nonisolated var animatableData: Double {
    get { level }
    set { level = newValue }
  }

  static func text(_ level: Double) -> String {
    "level \(Int((level * 100_000).rounded()))"
  }

  var body: some View {
    let _ = log.values.append(level)
    Text(Self.text(level))
  }
}

/// A view modifier that conforms to `Animatable` and moves its content right
/// by ten columns at progress 0 and none at progress 1.
private struct HarnessShift: ViewModifier, Animatable {
  var progress: Double
  let log: HarnessLog

  nonisolated var animatableData: Double {
    get { progress }
    set { progress = newValue }
  }

  static func indent(_ progress: Double) -> Int {
    max(0, min(10, Int((10 * (1 - progress)).rounded())))
  }

  func body(content: Content) -> some View {
    let _ = log.values.append(progress)
    content.padding(.leading, Self.indent(progress))
  }
}

/// A view under `transition(_:)` that the `t` key inserts and removes inside
/// an 800 ms linear animation with a completion.
private struct HarnessTransitionScene: View {
  @State private var isShown = false
  let log: HarnessLog

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("keys")
        .focusable()
        .onKeyPress(.character("t")) { _ in
          withAnimation(HarnessTiming.linear) {
            isShown.toggle()
          } completion: {
            log.completions += 1
          }
          return .handled
        }
      if isShown {
        Text("PRESENT")
          .transition(
            .modifier(
              active: HarnessShift(progress: 0, log: log),
              identity: HarnessShift(progress: 1, log: log)))
      }
    }
    .frame(width: 24, height: 3, alignment: .topLeading)
  }
}

private struct HarnessSwitchScene: View {
  @State private var isOn = false

  var body: some View {
    Text(isOn ? "switch on" : "switch off")
      .focusable()
      .onKeyPress(.character("s")) { _ in
        isOn.toggle()
        return .handled
      }
      .frame(width: 20, height: 2, alignment: .topLeading)
  }
}

private struct HarnessCounterScene: View {
  @State private var count = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Add") { count += 1 }
      Text("count \(count)")
    }
    .frame(width: 20, height: 6, alignment: .topLeading)
  }
}

private struct HarnessHoldScene: View {
  let log: HarnessLog

  var body: some View {
    Text("Hold")
      .onLongPressGesture(minimumDuration: .milliseconds(500)) {
        log.count += 1
      }
      .frame(width: 20, height: 3, alignment: .topLeading)
  }
}

private struct HarnessFieldScene: View {
  @State private var text = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      TextField("Name", text: $text)
      Text("typed:\(text):")
    }
    .frame(width: 30, height: 8, alignment: .topLeading)
  }
}

/// A view whose state the test writes through a binding it captured, beside
/// a value the view graph cannot observe.
private struct HarnessNumberScene: View {
  @State private var number = 0
  let log: HarnessLog

  var body: some View {
    let _ = capture()
    Text("number \(number) plain \(log.plain)")
      .frame(width: 30, height: 2, alignment: .topLeading)
  }

  private func capture() {
    log.number = $number
  }
}

/// A view whose `q` key asks the session to end and records the answer. It
/// records every other key it gets.
private struct HarnessTerminationScene: View {
  @Environment(\.requestTermination) private var requestTermination
  let log: HarnessLog

  var body: some View {
    let terminate = requestTermination
    Text("quit")
      .focusable()
      .onKeyPress { key in
        if key == KeyPress(.character("q")) {
          log.answers.append(terminate())
        } else {
          log.keys.append(key)
        }
        return .handled
      }
      .frame(width: 20, height: 2, alignment: .topLeading)
  }
}

/// A view whose `l` key opens a link and whose `w` key writes to the
/// clipboard, each through the action the run loop put in the environment.
/// It records what the action answered.
private struct HarnessHostActionsScene: View {
  @Environment(\.openLinkAction) private var openLinkAction
  @Environment(\.clipboardWriteAction) private var clipboardWriteAction
  let log: HarnessLog

  var body: some View {
    let open = openLinkAction
    let write = clipboardWriteAction
    Text("host")
      .focusable()
      .onKeyPress { key in
        if key == KeyPress(.character("l")) {
          // A scheme no program is registered for.
          log.answers.append(open("swifttui-harness-test://nowhere"))
        } else if key == KeyPress(.character("w")) {
          log.answers.append(write("text"))
        }
        return .handled
      }
      .frame(width: 20, height: 2, alignment: .topLeading)
  }
}

/// A view whose `c` key runs whatever the test put in the log.
private struct HarnessCallbackScene: View {
  let log: HarnessLog

  var body: some View {
    Text("callback")
      .focusable()
      .onKeyPress(.character("c")) { _ in
        log.action?()
        return .handled
      }
      .frame(width: 20, height: 2, alignment: .topLeading)
  }
}

/// A view that never settles once its `r` key is pressed: every change of
/// its state changes its state again.
private struct HarnessRestlessScene: View {
  @State private var ticks = 0

  var body: some View {
    Text("ticks \(ticks)")
      .focusable()
      .onKeyPress(.character("r")) { _ in
        ticks += 1
        return .handled
      }
      .onChange(of: ticks) {
        ticks += 1
      }
      .frame(width: 20, height: 2, alignment: .topLeading)
  }
}

@MainActor
@Observable
private final class HarnessModel {
  var count = 0
}

private struct HarnessModelScene: View {
  let model: HarnessModel

  var body: some View {
    Text("model \(model.count)")
      .frame(width: 20, height: 2, alignment: .topLeading)
  }
}

/// A view whose task tells the test when its body starts, waits to be
/// cancelled, and tells the test when its body ends.
private struct HarnessTaskScene: View {
  let started: AsyncEvent
  let ended: AsyncEvent

  var body: some View {
    Text("task")
      .task { [started, ended] in
        started.fire()
        await suspendUntilCancelled()
        ended.fire()
      }
  }
}

/// One row of the frame a harness presented last, without its trailing
/// spaces.
@MainActor
private func harnessRow<Content: View>(
  _ harness: RunLoopTestHarness<Content>, _ row: Int
) -> String {
  let lines = harness.lines
  guard lines.indices.contains(row) else {
    return ""
  }
  var characters = Array(lines[row])
  while characters.last == " " {
    characters.removeLast()
  }
  return String(characters)
}

/// The cell of the first character of `text` in the frame a harness
/// presented last.
@MainActor
private func harnessCell<Content: View>(
  of text: String, in harness: RunLoopTestHarness<Content>
) -> CellPoint? {
  let needle = Array(text)
  for (row, line) in harness.lines.enumerated() {
    let characters = Array(line)
    guard !needle.isEmpty, characters.count >= needle.count else {
      continue
    }
    for column in 0...(characters.count - needle.count)
    where Array(characters[column..<(column + needle.count)]) == needle {
      return CellPoint(x: column, y: row)
    }
  }
  return nil
}

private func harnessMilliseconds(_ duration: Duration) -> Double {
  let components = duration.components
  return Double(components.seconds) * 1000 + Double(components.attoseconds) / 1e15
}
