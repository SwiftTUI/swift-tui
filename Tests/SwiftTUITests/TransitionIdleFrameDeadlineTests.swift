@_spi(Testing) import SwiftTUITestSupport
import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// A view under `.transition(_:)` that is at rest asks for no frame
/// (STUI-1547).
///
/// A `.transition(_:)` modifier registers what to do when its view is
/// inserted or removed. The registration is not animation work: an insertion
/// or a removal that plays puts its own animations in the controller, and
/// those arm the frames. So a scene with such a view in it and nothing in
/// flight arms no frame deadline, and the run loop sleeps until something
/// asks the scheduler for a frame: an input, a state write, a signal or a
/// deadline armed elsewhere.
///
/// Every test drives the real run loop with `RunLoopTestHarness` on its
/// virtual clock. Nothing sleeps. `nextWake` is what the scheduler has armed,
/// and `advance(by:)` returns the number of frames presented.
@MainActor
@Suite("A transition at rest arms no frame deadline", .serialized)
struct TransitionIdleFrameDeadlineTests {
  private static let size = CellSize(width: 24, height: 3)
  private static let toggleKey = KeyPress(.character("t"))
  private static let startKey = KeyPress(.character("g"))
  /// A key no view of the scenes handles. It gets the frame an input gets.
  private static let otherKey = KeyPress(.character("x"))
  /// One frame of the run loop's animation cadence.
  private static let cadence = Duration.milliseconds(33)

  // MARK: - At rest

  @Test(
    "a view present from the first frame arms nothing, and an input still gets its frame",
    arguments: IdleTransition.allCases)
  func presentFromTheFirstFrame(kind: IdleTransition) throws {
    let log = IdleLog()
    let harness = try RunLoopTestHarness(size: Self.size) {
      IdleToggleScene(shown: true, transition: kind.transition(log), change: .animated, log: log)
    }
    defer { harness.shutdown() }
    #expect(idleRow(harness, 1) == "PRESENT")

    // The transition is registered and nothing animates: no frame is armed.
    try Self.expectRest(harness, "after the first frame")

    // An input gets its frame, and that frame arms nothing either.
    let presented = harness.frameCount
    try harness.press(Self.otherKey)
    #expect(harness.frameCount == presented + 1)
    #expect(idleRow(harness, 1) == "PRESENT")
    try Self.expectRest(harness, "after an input")
  }

  // MARK: - Insertion

  @Test(
    "an insertion starts on the frame of its key press, runs on the cadence and then arms nothing",
    arguments: IdleTransition.allCases, [IdleChange.animated, .animatedWithCompletion])
  func insertion(kind: IdleTransition, change: IdleChange) throws {
    let log = IdleLog()
    let harness = try RunLoopTestHarness(size: Self.size) {
      IdleToggleScene(shown: false, transition: kind.transition(log), change: change, log: log)
    }
    defer { harness.shutdown() }
    #expect(idleRow(harness, 1) == "")
    #expect(harness.nextWake == nil)

    // The key press renders one frame, at the instant of the press. That
    // frame is the first frame of the transition: it draws the view where
    // the transition starts, and it arms the next frame of the animation.
    let presented = harness.frameCount
    try harness.press(Self.toggleKey)
    let start = harness.now
    #expect(start == .zero)
    #expect(harness.frameCount == presented + 1)
    #expect(harness.nextWake == start.advanced(by: Self.cadence))
    let firstFrame = harness.frame
    #expect(idleRow(harness, 1) == kind.insertionOriginRow)
    if kind.readsAnimatableValue {
      // The body ran with the data of the `willAppear` phase.
      #expect(log.values.last == 0)
    }
    #expect(log.completions == 0)

    // The frames follow each other on the cadence until the insertion has
    // settled. Then nothing is armed.
    let run = try Self.runToRest(harness, "insertion")
    #expect(run.turns == kind.insertionTurns, "\(run.turns) frames after the key press")
    #expect(idleRow(harness, 1) == "PRESENT")
    // The transition drew its end state on the frame at 825 ms, the first
    // deadline past the curve, and the first frame was another picture.
    let endFrame = try #require(run.frameAtCurveEnd)
    #expect(firstFrame != endFrame)
    if run.turns > 25 {
      // The frame after it changed nothing.
      #expect(harness.frame == endFrame)
    }
    if kind.readsAnimatableValue {
      #expect(log.values.last == 1)
    }
    #expect(log.completions == (change == .animatedWithCompletion ? 1 : 0))
    try Self.expectRest(harness, "after the insertion")

    // A later input still gets its frame. That frame is the scene at rest,
    // rendered for the input and not for the transition, and it is the
    // picture the transition ended on.
    let settled = harness.frameCount
    try harness.press(Self.otherKey)
    #expect(harness.frameCount == settled + 1)
    #expect(harness.frame == endFrame)
    try Self.expectRest(harness, "after a later input")
  }

  @Test("an insertion without an animation shows the view at once and arms nothing")
  func insertionWithoutAnimation() throws {
    for kind in IdleTransition.allCases {
      let log = IdleLog()
      let harness = try RunLoopTestHarness(size: Self.size) {
        IdleToggleScene(shown: false, transition: kind.transition(log), change: .plain, log: log)
      }
      defer { harness.shutdown() }

      let presented = harness.frameCount
      try harness.press(Self.toggleKey)
      #expect(harness.frameCount == presented + 1, "\(kind)")
      #expect(idleRow(harness, 1) == "PRESENT", "\(kind)")
      try Self.expectRest(harness, "\(kind), after the insertion")
    }
  }

  // MARK: - Removal

  @Test(
    "a removal starts on the frame of its key press, runs on the cadence and then arms nothing",
    arguments: IdleTransition.allCases, [IdleChange.animated, .animatedWithCompletion])
  func removal(kind: IdleTransition, change: IdleChange) throws {
    let log = IdleLog()
    let harness = try RunLoopTestHarness(size: Self.size) {
      IdleToggleScene(shown: true, transition: kind.transition(log), change: change, log: log)
    }
    defer { harness.shutdown() }
    #expect(idleRow(harness, 1) == "PRESENT")
    try Self.expectRest(harness, "before the removal")

    // The key press renders one frame, at the instant of the press. The
    // view has left the scene, and that frame still draws all of it: the
    // removal starts from what is on screen, and arms its next frame.
    let presented = harness.frameCount
    try harness.press(Self.toggleKey)
    let start = harness.now
    #expect(harness.frameCount == presented + 1)
    #expect(idleRow(harness, 1) == "PRESENT")
    #expect(harness.nextWake == start.advanced(by: Self.cadence))
    #expect(log.completions == 0)

    // The frames follow each other on the cadence until nothing of the view
    // is left. No frame is armed after the one that ends the removal.
    let run = try Self.runToRest(harness, "removal")
    #expect(run.turns == IdleTransition.removalTurns, "\(run.turns) frames after the key press")
    #expect(idleRow(harness, 1) == "")
    // Nothing of the view was left on the frame at 825 ms, the first
    // deadline past the curve, and the frame after it changed nothing.
    let endFrame = try #require(run.frameAtCurveEnd)
    #expect(run.turns > 25)
    #expect(harness.frame == endFrame)
    if kind.readsAnimatableValue {
      // The frame that ends the removal draws nothing of the view, so the
      // body's last evaluation is its last sample, at 792 ms.
      let last = try #require(log.values.last)
      #expect(abs(last - (1 - 792.0 / 800)) < 1e-9, "\(last)")
    }
    #expect(log.completions == (change == .animatedWithCompletion ? 1 : 0))
    try Self.expectRest(harness, "after the removal")

    // A frame rendered at rest, for an input, is the picture the removal
    // ended on.
    var settled = harness.frameCount
    try harness.press(Self.otherKey)
    #expect(harness.frameCount == settled + 1)
    #expect(harness.frame == endFrame)
    try Self.expectRest(harness, "after a later input")

    // A later key press inserts the view again, on its own frame.
    settled = harness.frameCount
    try harness.press(Self.toggleKey)
    #expect(harness.frameCount == settled + 1)
    #expect(harness.nextWake == harness.now.advanced(by: Self.cadence))
  }

  @Test("a view that leaves with the identity transition is gone at once, and nothing is armed")
  func removalWithIdentityTransition() throws {
    let log = IdleLog()
    let harness = try RunLoopTestHarness(size: Self.size) {
      IdleToggleScene(shown: true, transition: .identity, change: .animated, log: log)
    }
    defer { harness.shutdown() }
    #expect(idleRow(harness, 1) == "PRESENT")
    try Self.expectRest(harness, "before the removal")

    // The identity transition plays nothing, inside an animation too.
    let presented = harness.frameCount
    try harness.press(Self.toggleKey)
    #expect(harness.frameCount == presented + 1)
    #expect(idleRow(harness, 1) == "")
    try Self.expectRest(harness, "after the removal")

    // And back: the insertion plays nothing and arms nothing.
    try harness.press(Self.toggleKey)
    #expect(idleRow(harness, 1) == "PRESENT")
    try Self.expectRest(harness, "after the insertion")
  }

  @Test("a removal without an animation is over at once and arms nothing")
  func removalWithoutAnimation() throws {
    for kind in IdleTransition.allCases {
      let log = IdleLog()
      let harness = try RunLoopTestHarness(size: Self.size) {
        IdleToggleScene(shown: true, transition: kind.transition(log), change: .plain, log: log)
      }
      defer { harness.shutdown() }

      let presented = harness.frameCount
      try harness.press(Self.toggleKey)
      #expect(harness.frameCount == presented + 1, "\(kind)")
      #expect(idleRow(harness, 1) == "", "\(kind)")
      try Self.expectRest(harness, "\(kind), after the removal")
    }
  }

  // MARK: - Beside another animation

  @Test(
    "beside a view under a transition, the frames of a finite animation stop when it ends",
    arguments: IdleTransition.allCases)
  func finiteAnimationBesideATransition(kind: IdleTransition) throws {
    let log = IdleLog()
    let harness = try RunLoopTestHarness(size: Self.size) {
      IdleGaugeScene(transition: kind.transition(IdleLog()), log: log)
    }
    defer { harness.shutdown() }
    #expect(idleRow(harness, 1) == "PRESENT")
    #expect(idleRow(harness, 2) == IdleGauge.text(0))
    try Self.expectRest(harness, "before the animation")

    // The key starts an 800 ms linear animation of the gauge, with a
    // completion. The view under the transition does not change.
    try harness.press(Self.startKey)
    let start = harness.now
    #expect(log.values.last == 0)
    #expect(harness.nextWake == start.advanced(by: Self.cadence))

    // Twenty-five deadlines: the first one past the 800 ms shows the target.
    for tick in 1...25 {
      let presented = harness.frameCount
      #expect(try harness.advanceToNextWake(), "tick \(tick)")
      #expect(harness.frameCount == presented + 1, "tick \(tick)")
      #expect(harness.now == start.advanced(by: Self.cadence * tick), "tick \(tick)")
      let expected = min(1, Double(33 * tick) / 800)
      let value = try #require(log.values.last)
      #expect(abs(value - expected) < 1e-9, "tick \(tick): \(value)")
      #expect(idleRow(harness, 1) == "PRESENT", "tick \(tick)")
      #expect(idleRow(harness, 2) == IdleGauge.text(expected), "tick \(tick)")
      #expect(log.completions == (tick == 25 ? 1 : 0), "tick \(tick)")
    }

    // The animation has ended. The transition keeps nothing armed.
    try Self.expectRest(harness, "after the animation")
    #expect(log.completions == 1)
  }

  @Test("a matched-geometry swap of two views under transitions travels, settles and arms nothing")
  func matchedGeometrySwap() throws {
    let log = IdleLog()
    let harness = try RunLoopTestHarness(size: Self.size) { IdleMatchedScene(log: log) }
    defer { harness.shutdown() }
    #expect(idleRow(harness, 1) == "HERO")
    try Self.expectRest(harness, "before the swap")

    // The key swaps the view that holds the key for one twenty columns to
    // the right. The departing view plays its removal and the arriving one
    // its insertion, and both travel the path between the two places.
    let presented = harness.frameCount
    try harness.press(Self.toggleKey)
    let start = harness.now
    #expect(harness.frameCount == presented + 1)
    #expect(harness.nextWake == start.advanced(by: Self.cadence))

    // Half way through the 800 ms the view is between the two places.
    for tick in 1...12 {
      #expect(try harness.advanceToNextWake(), "tick \(tick)")
      #expect(harness.now == start.advanced(by: Self.cadence * tick), "tick \(tick)")
    }
    let midway = idleRow(harness, 1)
    let indent = midway.prefix { $0 == " " }.count
    #expect(midway.contains("HERO"), "\(harness.lines)")
    #expect((1..<20).contains(indent), "\(harness.lines)")
    #expect(log.completions == 0)

    // The swap ends, its completion fires once, and nothing is armed.
    let run = try Self.runToRest(harness, "swap")
    #expect(run.turns == IdleTransition.removalTurns - 12, "\(run.turns) more frames")
    #expect(idleRow(harness, 1) == String(repeating: " ", count: 20) + "HERO")
    #expect(log.completions == 1)
    try Self.expectRest(harness, "after the swap")
  }

  // MARK: - Helpers

  /// Nothing is armed: no frame is due, a second of virtual time presents
  /// none, and a step finds none.
  private static func expectRest<Content: View>(
    _ harness: RunLoopTestHarness<Content>, _ label: String
  ) throws {
    #expect(harness.nextWake == nil, "\(label)")
    let presented = harness.frameCount
    #expect(try harness.advance(by: .seconds(1)) == 0, "\(label)")
    #expect(harness.frameCount == presented, "\(label)")
    #expect(try harness.advanceToNextWake() == false, "\(label)")
    #expect(harness.nextWake == nil, "\(label)")
  }

  /// Renders every armed frame until none is armed. Each is one frame, 33 ms
  /// after the one before. Returns how many there were, and the frame of the
  /// 25th: the one at 825 ms, the first deadline past the 800 ms curve.
  private static func runToRest<Content: View>(
    _ harness: RunLoopTestHarness<Content>, _ label: String
  ) throws -> (turns: Int, frameAtCurveEnd: RasterSurface?) {
    var turns = 0
    var frameAtCurveEnd: RasterSurface?
    var previous = harness.now
    var presented = harness.frameCount
    while try harness.advanceToNextWake() {
      turns += 1
      #expect(harness.now == previous.advanced(by: cadence), "\(label), frame \(turns)")
      #expect(harness.frameCount == presented + 1, "\(label), frame \(turns)")
      previous = harness.now
      presented = harness.frameCount
      if turns == 25 {
        frameAtCurveEnd = harness.frame
      }
      // Twice the frames of the animation: a scene that keeps a frame armed
      // at rest never leaves this loop by itself.
      try #require(turns <= 52, "\(label): a frame is still armed after \(turns) frames")
    }
    return (turns, frameAtCurveEnd)
  }
}

/// The animation controller's side of the same rule: a registration is not
/// work, and the work of an insertion or a removal is.
@MainActor
@Suite("Transition registrations are not animation work")
struct TransitionIdleFrameDeadlineControllerTests {
  private static let proposal = ProposedSize(width: .finite(24), height: .finite(3))

  @Test("a transition registered in every registration map needs no continued frames")
  func registrationAloneNeedsNoFrames() {
    let controller = AnimationController()
    let identity = testIdentity("TransitionIdle", "Leaf")
    let nodeID = ViewNodeID(rawValue: 7)

    // Two collections put the registration in the current map, the previous
    // map and the pending map.
    for _ in 0..<2 {
      controller.beginTransitionCollection()
      controller.registerTransition(
        for: identity, viewNodeID: nodeID, transition: AnyTransition.opacity)
      controller.finishTransitionCollection()
    }
    let state = controller.debugStateSnapshot()
    #expect(state.transitionNodeIDs == [nodeID])
    #expect(state.previousTransitionNodeIDs == [nodeID])
    #expect(state.pendingTransitionNodeIDs == [nodeID])
    #expect(state.activeAnimationKeys.isEmpty)
    #expect(state.removingNodeIDs.isEmpty)

    #expect(!controller.requiresContinuedAnimationFrames)
  }

  @Test(
    "a rendered view at rest under a transition needs no continued frames",
    arguments: IdleTransition.allCases)
  func renderedViewAtRestNeedsNoFrames(kind: IdleTransition) {
    let renderer = DefaultRenderer()
    let controller = renderer.internalAnimationController
    let rootIdentity = testIdentity("TransitionIdle", "Root")
    let transition = kind.transition(IdleLog())

    // Twice, so the second frame has the registration of the first as its
    // previous one.
    for _ in 0..<2 {
      _ = renderer.render(
        IdlePresenceProbe(shown: true, transition: transition),
        context: ResolveContext(identity: rootIdentity),
        proposal: Self.proposal)
    }
    let state = controller.debugStateSnapshot()
    #expect(!state.transitionNodeIDs.isEmpty)
    #expect(!state.previousTransitionNodeIDs.isEmpty)
    #expect(state.activeAnimationKeys.isEmpty)
    #expect(state.removingNodeIDs.isEmpty)

    #expect(!controller.lastTickResult.hasPendingWork)
    #expect(!controller.requiresContinuedAnimationFrames)
  }

  @Test(
    "an insertion and a removal in flight need continued frames",
    arguments: IdleTransition.allCases)
  func transitionInFlightNeedsFrames(kind: IdleTransition) {
    let renderer = DefaultRenderer()
    let controller = renderer.internalAnimationController
    let rootIdentity = testIdentity("TransitionIdle", "Root")
    let transition = kind.transition(IdleLog())
    let animation = Animation.linear(duration: .milliseconds(800))
    controller.register(animation)
    var animate = TransactionSnapshot()
    animate.animationRequest = .animate(animation.animationBox)

    _ = renderer.render(
      IdlePresenceProbe(shown: false, transition: transition),
      context: ResolveContext(identity: rootIdentity),
      proposal: Self.proposal)
    #expect(!controller.requiresContinuedAnimationFrames)

    // The insertion puts animations in the controller: that is the work.
    _ = renderer.render(
      IdlePresenceProbe(shown: true, transition: transition),
      context: ResolveContext(identity: rootIdentity, transaction: animate),
      proposal: Self.proposal)
    #expect(!controller.debugStateSnapshot().activeAnimationKeys.isEmpty)
    #expect(controller.lastTickResult.hasPendingWork)
    #expect(controller.requiresContinuedAnimationFrames)

    // The removal puts an overlay in the controller.
    _ = renderer.render(
      IdlePresenceProbe(shown: false, transition: transition),
      context: ResolveContext(identity: rootIdentity, transaction: animate),
      proposal: Self.proposal)
    #expect(!controller.debugStateSnapshot().removingNodeIDs.isEmpty)
    #expect(controller.lastTickResult.hasPendingWork)
    #expect(controller.requiresContinuedAnimationFrames)
  }
}

// MARK: - Fixtures

/// What a test and its scene share.
@MainActor
private final class IdleLog {
  /// The data each evaluation of an animated site ran with, in order.
  var values: [Double] = []
  var completions = 0
}

@MainActor
private enum IdleTiming {
  static let linear = Animation.linear(duration: .milliseconds(800))
}

/// The transitions the tests put a view under.
enum IdleTransition: String, CaseIterable, Sendable, CustomTestStringConvertible {
  /// A built-in that animates a property of the view in the resolved tree.
  case opacity
  /// A built-in that moves the placed view, after layout.
  case move
  /// A built-in that resizes the placed view, after layout.
  case scale
  /// A type that conforms to `Transition`, whose body changes a modifier
  /// value between its phases.
  case body
  /// A type that conforms to `Transition`, whose body holds a view modifier
  /// that conforms to `Animatable`.
  case animatableBody

  var testDescription: String { rawValue }

  /// Whether the transition's body runs with interpolated data, which it
  /// records in the log.
  var readsAnimatableValue: Bool {
    self == .animatableBody
  }

  /// The row of the view on the first frame of an insertion: where the
  /// transition starts. The built-ins start with nothing of the view on the
  /// surface, and the two bodies start ten columns to the right.
  var insertionOriginRow: String {
    switch self {
    case .opacity, .move, .scale: ""
    case .body, .animatableBody: String(repeating: " ", count: 10) + "PRESENT"
    }
  }

  /// How many frames an 800 ms linear insertion takes after the frame of
  /// its key press.
  ///
  /// Twenty-five deadlines of the cadence reach 825 ms, the first one past
  /// the curve, and every transition draws its end there. An animation the
  /// frame head samples also stops there: the head's tick sees the curve end
  /// and reports nothing pending. A move and a scale are sampled by the
  /// placed pass, which runs after the head's tick. The run loop asks for
  /// the next frame after the commit, from the result of that tick, and the
  /// tick ran while the animation was still in flight. So a 26th frame is
  /// armed. It finds nothing in flight and arms nothing.
  var insertionTurns: Int {
    switch self {
    case .opacity, .body, .animatableBody: 25
    case .move, .scale: 26
    }
  }

  /// How many frames an 800 ms linear removal takes after the frame of its
  /// key press. The placed pass samples a removal too, whatever it plays, so
  /// a removal takes the 26th frame as well (see ``insertionTurns``). With a
  /// completion that frame is also the one that drops the removal's overlay.
  static let removalTurns = 26

  @MainActor
  fileprivate func transition(_ log: IdleLog) -> AnyTransition {
    switch self {
    case .opacity:
      .opacity
    case .move:
      .move(edge: .leading)
    case .scale:
      .scale
    case .body:
      AnyTransition(IdleIndent())
    case .animatableBody:
      AnyTransition(IdleSlide(log: log))
    }
  }
}

/// How the `t` key of `IdleToggleScene` changes the state.
enum IdleChange: String, Sendable, CustomTestStringConvertible {
  /// Outside any animation.
  case plain
  /// Inside an 800 ms linear animation.
  case animated
  /// Inside an 800 ms linear animation with a completion.
  case animatedWithCompletion

  var testDescription: String { rawValue }
}

/// A transition with a body: the content is indented by ten columns outside
/// the identity phase.
private struct IdleIndent: Transition {
  func body(content: Content, phase: TransitionPhase) -> some View {
    content.padding(.leading, phase.isIdentity ? 0 : 10)
  }
}

/// A transition whose body reads an `Animatable` value: `IdleShift` gets
/// data 1 in the identity phase and 0 outside it.
private struct IdleSlide: Transition {
  let log: IdleLog

  func body(content: Content, phase: TransitionPhase) -> some View {
    content.modifier(IdleShift(progress: phase.isIdentity ? 1 : 0, log: log))
  }
}

/// A view modifier that conforms to `Animatable`. It records the data of
/// each evaluation and indents its content by ten columns at 0 and by none
/// at 1.
private struct IdleShift: ViewModifier, Animatable {
  var progress: Double
  let log: IdleLog

  nonisolated var animatableData: Double {
    get { progress }
    set { progress = newValue }
  }

  func body(content: Content) -> some View {
    let _ = log.values.append(progress)
    content.padding(.leading, max(0, min(10, Int((10 * (1 - progress)).rounded()))))
  }
}

/// A view under a transition that the `t` key inserts and removes.
private struct IdleToggleScene: View {
  @State private var isShown: Bool
  let transition: AnyTransition
  let change: IdleChange
  let log: IdleLog

  init(shown: Bool, transition: AnyTransition, change: IdleChange, log: IdleLog) {
    _isShown = State(initialValue: shown)
    self.transition = transition
    self.change = change
    self.log = log
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("keys")
        .focusable()
        .onKeyPress(.character("t")) { _ in
          toggle()
          return .handled
        }
      if isShown {
        Text("PRESENT").transition(transition)
      }
    }
    .frame(width: 24, height: 3, alignment: .topLeading)
  }

  private func toggle() {
    switch change {
    case .plain:
      isShown.toggle()
    case .animated:
      withAnimation(IdleTiming.linear) {
        isShown.toggle()
      }
    case .animatedWithCompletion:
      withAnimation(IdleTiming.linear) {
        isShown.toggle()
      } completion: {
        log.completions += 1
      }
    }
  }
}

/// A view under a transition that stays, above a gauge whose level the `g`
/// key animates from 0 to 1 over 800 ms, with a completion.
private struct IdleGaugeScene: View {
  @State private var level = 0.0
  let transition: AnyTransition
  let log: IdleLog

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("keys")
        .focusable()
        .onKeyPress(.character("g")) { _ in
          withAnimation(IdleTiming.linear) {
            level = 1
          } completion: {
            log.completions += 1
          }
          return .handled
        }
      Text("PRESENT").transition(transition)
      IdleGauge(level: level, log: log)
    }
    .frame(width: 24, height: 3, alignment: .topLeading)
  }
}

/// Two views that hold one matched-geometry key in turn, twenty columns
/// apart, each under a transition. The `t` key swaps them inside an 800 ms
/// linear animation with a completion.
private struct IdleMatchedScene: View {
  @State private var isLeading = true
  let log: IdleLog

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("keys")
        .focusable()
        .onKeyPress(.character("t")) { _ in
          withAnimation(IdleTiming.linear) {
            isLeading.toggle()
          } completion: {
            log.completions += 1
          }
          return .handled
        }
      if isLeading {
        Text("HERO")
          .matchedGeometryEffect(id: "hero")
          .frame(width: 24, alignment: .leading)
          .transition(.opacity)
      } else {
        Text("HERO")
          .matchedGeometryEffect(id: "hero")
          .frame(width: 24, alignment: .trailing)
          .transition(.opacity)
      }
    }
    .frame(width: 24, height: 3, alignment: .topLeading)
  }
}

/// A view that conforms to `Animatable`: its body runs with the sample of
/// every frame, records it, and draws it as a number of hundred-thousandths.
private struct IdleGauge: View, Animatable {
  var level: Double
  let log: IdleLog

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

/// A view under a transition whose presence the caller sets, for a renderer
/// without a run loop.
private struct IdlePresenceProbe: View {
  let shown: Bool
  let transition: AnyTransition

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("host")
      if shown {
        Text("PRESENT").transition(transition)
      }
    }
  }
}

/// One row of the frame a harness presented last, without its trailing
/// spaces.
@MainActor
private func idleRow<Content: View>(
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
