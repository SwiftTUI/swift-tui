import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIGraph
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// Custom `Animatable` views and view modifiers (STUI-1546): the body of a
/// conformer runs again on every animation tick with interpolated
/// `animatableData`, for content that is live in the view graph.
///
/// Every test drives the real run loop on an injected frame clock, one
/// scheduler wake at a time, and reads the values the bodies were evaluated
/// with. Nothing waits. The file uses only API that existed before the
/// change, so it compiles against the earlier engine, where a conformer's
/// body ran once, at its end value.
@MainActor
@Suite("Animatable value animation", .serialized)
struct AnimatableValueAnimationTests {
  private static let linear = Animation.linear(duration: .milliseconds(800))
  /// One frame of the 33 ms cadence, as a share of the 800 ms animation.
  private static let step = 33.0 / 800.0
  /// A spring that overshoots its target.
  private static let spring = Animation.spring(duration: .milliseconds(600), bounce: 0.5)

  // MARK: - Recorded values

  @Test("a modifier's body runs with every sample of a linear animation")
  func modifierReceivesEveryLinearSample() throws {
    let probe = try AnimatableValueProbe(named: "modifier-linear") { progress, log in
      Text("PRESENT").modifier(ProgressFade(progress: progress, log: log))
    }
    defer { probe.shutdown() }
    try probe.run { _ in
      let frames = try probe.animate(to: 1, Self.linear)
      try Self.expectLinearRun(frames, in: probe)
      // The owner's body ran for the samples. The view that holds the state
      // ran for the mount and for the write.
      if animatableProbeEvaluatesSelectively {
        #expect(probe.log.evaluations["root"] == 2)
      }
    }
  }

  @Test("a view's body runs with every sample of a linear animation")
  func viewReceivesEveryLinearSample() throws {
    let probe = try AnimatableValueProbe(named: "view-linear") { progress, log in
      LevelGauge(level: progress, log: log)
    }
    defer { probe.shutdown() }
    try probe.run { _ in
      let frames = try probe.animate(to: 1, Self.linear)
      try Self.expectLinearRun(frames, in: probe)
      if animatableProbeEvaluatesSelectively {
        #expect(probe.log.evaluations["root"] == 2)
      }
      // What the body drew followed the samples: the bar grew a cell at a
      // time and ended full.
      let bars = frames.map { $0.line(0).count }
      #expect(bars == bars.sorted(), "\(bars)")
      #expect(bars.first == 0 && bars.last == 10, "\(bars)")
      #expect(Set(bars).count > 5, "\(bars)")
    }
  }

  @Test("a view whose body root is a conditional or a Group gets every sample")
  func flattenedBodyRootsAnimate() throws {
    for root in ["conditional", "group"] {
      let probe = try AnimatableValueProbe(named: "flattened-\(root)") { progress, log in
        if root == "conditional" {
          BranchingGauge(level: progress, log: log)
        } else {
          GroupedGauge(level: progress, log: log)
        }
      }
      defer { probe.shutdown() }
      try probe.run { _ in
        // Such a view commits its branch's node in its own place, so the
        // identity it resolves at is not in the resolved tree. Its node is,
        // and that is what keeps the animation.
        let frames = try probe.animate(to: 1, Self.linear)
        try Self.expectLinearRun(frames, in: probe)
        #expect(probe.frame.contains("level 100"), "\(root): \(probe.frame)")
      }
    }
  }

  @Test("a spring delivers values beyond its target to a modifier and to a view")
  func springOvershoots() throws {
    for site in ["modifier", "view"] {
      let probe = try AnimatableValueProbe(named: "spring-\(site)") { progress, log in
        if site == "modifier" {
          Text("PRESENT").modifier(ProgressFade(progress: progress, log: log))
        } else {
          LevelGauge(level: progress, log: log)
        }
      }
      defer { probe.shutdown() }
      try probe.run { _ in
        let frames = try probe.animate(to: 1, Self.spring)
        let values = frames.compactMap(\.values.last)
        // A spring with bounce passes its target and comes back. The body
        // gets the values as they are: nothing clamps them to 0...1.
        let peak = try #require(values.max())
        #expect(peak > 1.02, "\(site): \(values)")
        #expect(values.first == 0, "\(site): \(values)")
        #expect(values.last == 1, "\(site): \(values)")
        #expect(frames.allSatisfy { $0.values.count == 1 }, "\(site)")
        #expect(probe.log.completions == 1, "\(site)")
      }
    }
  }

  @Test("animation(_:value:) drives the same samples as withAnimation")
  func valueAnimationModifierDrives() throws {
    let probe = try AnimatableValueProbe(named: "animation-value") { progress, log in
      Text("PRESENT")
        .modifier(ProgressFade(progress: progress, log: log))
        .animation(Self.linear, value: progress)
    }
    defer { probe.shutdown() }
    try probe.run { _ in
      // A plain state write: the modifier outside supplies the animation.
      let frames = try probe.animate(to: 1, nil)
      try Self.expectLinearRun(frames, in: probe, completions: 0)
    }
  }

  // MARK: - Interruption

  @Test("a linear animation retargeted in flight continues from its current sample")
  func linearRetargetContinues() throws {
    let probe = try AnimatableValueProbe(named: "retarget-linear") { progress, log in
      Text("PRESENT").modifier(ProgressFade(progress: progress, log: log))
    }
    defer { probe.shutdown() }
    try probe.run { _ in
      try probe.set(1, animation: Self.linear)
      var values = [try #require(probe.log.values.last)]
      for _ in 0..<12 {
        values.append(try #require(try probe.step()?.values.last))
      }
      // The write lands on the next frame of the cadence, so that frame is
      // both a tick of the animation in flight and the start of the new one.
      let turn = try probe.set(0, animation: Self.linear, atNextWake: true)
      values.append(try #require(turn.values.last))
      let retargetIndex = values.count - 1
      values.append(contentsOf: try probe.runToEnd().compactMap(\.values.last))

      // The frame of the retarget shows the next sample of the old line.
      #expect(abs(values[retargetIndex] - 13 * Self.step) < 1e-9, "\(values)")
      // No step is larger than one step of the first animation, and from
      // the retarget on the value falls to exactly zero.
      let steps = zip(values, values.dropFirst()).map { $1 - $0 }
      #expect(steps.allSatisfy { abs($0) <= Self.step + 1e-9 }, "\(steps)")
      #expect(steps[..<retargetIndex].allSatisfy { $0 > 0 }, "\(steps)")
      #expect(steps[retargetIndex...].allSatisfy { $0 < 0 }, "\(steps)")
      #expect(values.last == 0, "\(values)")
      // The first animation's completion fired when it was interrupted, the
      // second one's when it ended.
      #expect(probe.log.completions == 2)
      #expect(probe.controller.debugStateSnapshot().activeAnimationKeys.isEmpty)
    }
  }

  @Test("a spring retargeted in flight keeps the sign and the size of its velocity")
  func springRetargetKeepsVelocity() throws {
    let probe = try AnimatableValueProbe(named: "retarget-spring") { progress, log in
      Text("PRESENT").modifier(ProgressFade(progress: progress, log: log))
    }
    defer { probe.shutdown() }
    let smooth = Animation.spring(duration: .milliseconds(800), bounce: 0)
    try probe.run { _ in
      try probe.set(1, animation: smooth)
      var values = [try #require(probe.log.values.last)]
      for _ in 0..<5 {
        values.append(try #require(try probe.step()?.values.last))
      }
      // Reverse while the spring is moving fast.
      let turn = try probe.set(0, animation: smooth, atNextWake: true)
      values.append(try #require(turn.values.last))
      let retargetIndex = values.count - 1
      values.append(contentsOf: try probe.runToEnd().compactMap(\.values.last))

      let steps = zip(values, values.dropFirst()).map { $1 - $0 }
      let before = steps[retargetIndex - 1]
      let after = steps[retargetIndex]
      // The value was rising. The spring toward zero starts with that
      // velocity, so the first step after the retarget still rises, by about
      // as much, before the spring turns it round.
      #expect(before > 0 && after > 0, "\(steps)")
      #expect((0.5...1.1).contains(after / before), "\(after / before): \(steps)")
      let largest = try #require(steps[..<retargetIndex].map(abs).max())
      #expect(steps[retargetIndex...].allSatisfy { abs($0) <= largest * 1.5 }, "\(steps)")
      #expect(steps[(retargetIndex + 1)...].contains { $0 < 0 }, "\(steps)")
      #expect(values.last == 0, "\(values)")
    }
  }

  // MARK: - Confinement

  @Test("only the owner's subtree is evaluated again, and its content keeps its state")
  func evaluationIsConfinedToTheOwner() throws {
    let probe = try AnimatableValueProbe(named: "confinement") { progress, log in
      HostedCounter(log: log).modifier(ProgressFade(progress: progress, log: log))
    }
    defer { probe.shutdown() }
    try probe.run { _ in
      // Give the hosted content state of its own before the animation.
      _ = try probe.harness.clickText("count 0")
      #expect(probe.frame.contains("count 1"), "\(probe.frame)")
      let sibling = try #require(probe.log.evaluations["sibling"])
      let unrelated = try #require(probe.log.evaluations["unrelated"])
      let root = try #require(probe.log.evaluations["root"])

      let frames = try probe.animate(to: 1, Self.linear)
      // The modifier's body ran on every frame: for the write and for each
      // of the twenty-five ticks.
      #expect(frames.count == 26)
      #expect(frames.allSatisfy { $0.values.count == 1 }, "\(frames.map(\.values))")
      #expect(frames.last?.values == [1])
      // The views beside the owner ran once, for the state write, because
      // their parent's body ran: no tick reached them.
      if animatableProbeEvaluatesSelectively {
        #expect(probe.log.evaluations["root"] == root + 1)
        #expect(probe.log.evaluations["sibling"] == sibling + 1)
        #expect(probe.log.evaluations["unrelated"] == unrelated + 1)
      }
      // The content the modifier hosts stayed mounted through every
      // evaluation: its state is the one it had, and it appeared once.
      #expect(frames.allSatisfy { $0.frame.contains("count 1") })
      #expect(probe.log.appears == 1)
      #expect(probe.log.disappears == 0)
    }
  }

  // MARK: - What does not animate this way

  @Test("a modifier that does not conform is evaluated once and its output animates")
  func nonConformingModifierIsEvaluatedOnce() throws {
    let probe = try AnimatableValueProbe(named: "plain-modifier") { progress, log in
      Text("PRESENT").modifier(PlainProgressFade(progress: progress, log: log))
    }
    defer { probe.shutdown() }
    try probe.run { _ in
      let frames = try probe.animate(to: 1, Self.linear)
      // One evaluation, with the end value. The opacity the body wrote is a
      // property of the node and animates there, as before.
      if animatableProbeEvaluatesSelectively {
        #expect(probe.log.values == [0, 1])
      }
      #expect(Set(probe.log.values) == [0, 1])
      #expect(frames.first?.propertyAnimations == 1)
      #expect(frames.last?.propertyAnimations == 0)
      #expect(probe.log.completions == 1)
    }
  }

  @Test("a change without an animation evaluates the body once, at the end value")
  func changeWithoutAnAnimationSnaps() throws {
    for mode in ValueSnapMode.allCases {
      let probe = try AnimatableValueProbe(named: "snap-\(mode)", policy: mode.policy) {
        progress, log in
        Text("PRESENT").modifier(ProgressFade(progress: progress, log: log))
      }
      defer { probe.shutdown() }
      try probe.run { _ in
        switch mode {
        case .plainWrite:
          try probe.set(1, animation: nil)
        case .nilAnimation:
          try probe.set(1, animation: nil, disabling: true)
        case .disabledTransaction:
          let progress = try #require(probe.log.progress)
          withTransaction(\.disablesAnimations, true) { progress.wrappedValue = 1 }
          _ = try probe.harness.render()
        case .reduceMotion, .stableOutput:
          try probe.set(1, animation: Self.linear)
        }
        #expect(probe.log.values == [0, 1], "\(mode): \(probe.log.values)")
        #expect(
          probe.controller.debugStateSnapshot().activeAnimationKeys.isEmpty, "\(mode)")
        // Nothing follows: no later frame evaluates the body again.
        _ = try probe.runToEnd()
        #expect(probe.log.values == [0, 1], "\(mode): \(probe.log.values)")
      }
    }
  }

  @Test("Reduce Motion or stable output turned on in flight ends the animation at its target")
  func policyTurnedOnInFlightSettles() throws {
    for policy in [AnimatableValueProbePolicy.reduceMotion, .stableOutput] {
      let probe = try AnimatableValueProbe(named: "settle-\(policy)") { progress, log in
        Text("PRESENT").modifier(ProgressFade(progress: progress, log: log))
      }
      defer { probe.shutdown() }
      try probe.run { _ in
        try probe.set(1, animation: Self.linear)
        for _ in 0..<5 {
          _ = try probe.step()
        }
        #expect(abs((probe.log.values.last ?? -1) - 5 * Self.step) < 1e-9, "\(policy)")
        // The policy turns on at the next frame of the cadence. The body
        // runs with its target on that frame: it is not left at a sample of
        // an animation that no longer runs.
        let turn = try probe.switchPolicy(to: policy)
        #expect(turn.values.last == 1, "\(policy): \(turn.values)")
        #expect(turn.animationKeys == 0, "\(policy)")
        #expect(turn.completions == 1, "\(policy)")
        // Nothing follows: no later frame evaluates the body again.
        _ = try probe.runToEnd()
        #expect(probe.log.values.last == 1, "\(policy): \(probe.log.values)")
        #expect(probe.log.completions == 1, "\(policy)")
      }
    }
  }

  @Test("content and modifier that both conform animate as one value")
  func modifiedContentAnimatesAsOneValue() throws {
    let probe = try AnimatableValueProbe(named: "both-conform") { progress, log in
      LevelGauge(level: progress, log: log, secondary: true)
        .modifier(ProgressFade(progress: progress, log: log))
    }
    defer { probe.shutdown() }
    try probe.run { _ in
      let frames = try probe.animate(to: 1, Self.linear)
      // One animation, for the pair. Each part's body ran once a frame, and
      // both saw the same sample.
      #expect(frames.dropLast().allSatisfy { $0.animationKeys == 1 })
      #expect(frames.allSatisfy { $0.values.count == 1 && $0.secondary.count == 1 })
      #expect(frames.allSatisfy { $0.values == $0.secondary })
      #expect(frames.last?.values == [1])
      #expect(frames.last?.animationKeys == 0)
      let values = frames.compactMap(\.values.last)
      #expect(values == values.sorted() && Set(values).count == values.count, "\(values)")
    }
  }

  @Test("a conformer with no data starts no animation")
  func emptyAnimatableDataStartsNothing() throws {
    let probe = try AnimatableValueProbe(named: "empty-data") { progress, log in
      Text("PRESENT").modifier(EmptyDataBadge(label: progress == 0 ? "a" : "b", log: log))
    }
    defer { probe.shutdown() }
    try probe.run { _ in
      try probe.set(1, animation: Self.linear)
      #expect(probe.log.evaluations["badge"] == 2)
      #expect(probe.controller.debugStateSnapshot().activeAnimationKeys.isEmpty)
      _ = try probe.runToEnd()
      // The body ran for the write and never again.
      if animatableProbeEvaluatesSelectively {
        #expect(probe.log.evaluations["badge"] == 2)
      }
      #expect(probe.frame.contains("PRESENT b"))
    }
  }

  // MARK: - Off screen

  @Test("a value animation that is scrolled out of view runs to its end and is not elided")
  func offscreenAnimationCompletes() throws {
    let probe = try AnimatableValueProbe(named: "offscreen", size: .init(width: 20, height: 2)) {
      progress, log in
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(0..<30, id: \.self) { _ in Text("filler") }
          Text("PRESENT").modifier(ProgressFade(progress: progress, log: log))
        }
      }
      .frame(width: 20, height: 1)
    }
    defer { probe.shutdown() }
    try probe.run { _ in
      #expect(!probe.frame.contains("PRESENT"))
      let elided = probe.harness.runLoop.renderer.elidedFrameCount
      let frames = try probe.animate(to: 1, Self.linear)
      // The body is not on screen, and it still gets every sample: what it
      // does with one cannot be known without running it.
      try Self.expectLinearRun(frames, in: probe)
      #expect(probe.harness.runLoop.renderer.elidedFrameCount == elided)
      #expect(!probe.frame.contains("PRESENT"))
    }
  }

  // MARK: - The abortable renderer path

  @Test("the asynchronous renderer delivers the same samples")
  func asyncRendererDeliversTheSameSamples() async throws {
    let offsets = [0, 33, 66, 99, 400, 792, 825, 858]
    let sync = AnimatableValueFrames.run(named: "sync", at: offsets)
    let asynchronous = await AnimatableValueFrames.runAsync(named: "async", at: offsets)
    #expect(sync == asynchronous, "\(sync) / \(asynchronous)")
    let expected = offsets.map { min(1, Double($0) / 800) }
    #expect(sync.count == expected.count)
    for (value, expectation) in zip(sync, expected) {
      #expect(abs(value - expectation) < 1e-9, "\(sync)")
    }
    #expect(sync.last == 1)
  }

  @Test("an aborted frame neither loses a value animation nor advances it twice")
  func abortedFrameLeavesTheAnimationAlone() throws {
    let log = AnimatableValueLog()
    let renderer = DefaultRenderer()
    let controller = renderer.internalAnimationController
    let root = testIdentity("animatable-value", "aborted")
    let start = MonotonicInstant(offset: .seconds(100))
    var animated = TransactionSnapshot()
    animated.animationRequest = .animate(Self.linear.animationBox)
    func view(_ progress: Double) -> some View {
      Text("PRESENT").modifier(ProgressFade(progress: progress, log: log))
    }
    func render(_ progress: Double, transaction: TransactionSnapshot = .init(), at offset: Int) {
      _ = renderer.renderArtifacts(
        view(progress), context: .init(identity: root, transaction: transaction),
        proposal: AnimatableValueFrames.proposal,
        frameInstant: start.advanced(by: .milliseconds(offset)))
    }
    func abort(_ progress: Double, transaction: TransactionSnapshot = .init(), at offset: Int) {
      let draft = renderer.prepareFrameHeadForCancellationTesting(
        view(progress), context: .init(identity: root, transaction: transaction),
        proposal: AnimatableValueFrames.proposal,
        frameInstant: start.advanced(by: .milliseconds(offset)))
      renderer.abortPreparedFrameHeadForCancellationTesting(draft)
    }
    withAnimationSinks(controller) {
      controller.register(Self.linear)
      render(0, at: 0)

      // The frame that would start the animation is aborted. Its body ran
      // with the origin, and nothing of it stays: the frame that replaces it
      // starts the animation, from the origin.
      abort(1, transaction: animated, at: 0)
      #expect(log.values == [0, 0])
      #expect(controller.debugStateSnapshot().activeAnimationKeys.isEmpty)
      render(1, transaction: animated, at: 0)
      #expect(log.values.last == 0)
      #expect(controller.debugStateSnapshot().activeAnimationKeys.count == 1)

      render(1, at: 33)
      #expect(abs((log.values.last ?? -1) - Self.step) < 1e-9)

      // A tick is aborted. Its body ran with that tick's sample. The next
      // frame's sample is the one for its own instant: the aborted tick did
      // not move the animation, and it did not cost it a step.
      abort(1, at: 66)
      #expect(abs((log.values.last ?? -1) - 2 * Self.step) < 1e-9)
      render(1, at: 99)
      #expect(abs((log.values.last ?? -1) - 3 * Self.step) < 1e-9)

      // The frame that would end the animation is aborted: it is still in
      // flight afterwards, and the next frame ends it.
      abort(1, at: 825)
      #expect(log.values.last == 1)
      #expect(controller.debugStateSnapshot().activeAnimationKeys.count == 1)
      render(1, at: 858)
      #expect(log.values.last == 1)
      #expect(controller.debugStateSnapshot().activeAnimationKeys.isEmpty)
    }
  }

  // MARK: - Shared expectations

  /// The run of an 800 ms linear animation from 0 to 1 on the 33 ms cadence:
  /// the origin on the frame of the write, one evaluation a frame, a value
  /// that rises by one step a frame and ends at exactly 1, no property
  /// animation beside it, and the completion on the last frame.
  private static func expectLinearRun<Content: View>(
    _ frames: [AnimatableValueFrame],
    in probe: AnimatableValueProbe<Content>,
    completions: Int = 1
  ) throws {
    #expect(frames.count == 26, "\(frames.map(\.milliseconds))")
    #expect(frames.allSatisfy { $0.values.count == 1 }, "\(frames.map(\.values))")
    let values = frames.compactMap(\.values.last)
    #expect(values.first == 0, "\(values)")
    #expect(values.last == 1, "\(values)")
    #expect(values == values.sorted() && Set(values).count == values.count, "\(values)")
    for frame in frames {
      let expected = min(1, Double(frame.milliseconds) / 800)
      let value = try #require(frame.values.last)
      #expect(abs(value - expected) < 1e-9, "\(frame.milliseconds) ms: \(value)")
    }
    // The value animation is the only animation: what the body produced
    // from each sample was written as it was.
    #expect(frames.allSatisfy { $0.propertyAnimations == 0 })
    #expect(frames.dropLast().allSatisfy { $0.animationKeys == 1 })
    #expect(frames.last?.animationKeys == 0)
    // The completion fires on the frame that reaches the target, once.
    #expect(frames.dropLast().allSatisfy { $0.completions == 0 })
    #expect(frames.last?.completions == completions)
    #expect(probe.log.completions == completions)
  }
}

// MARK: - Fixtures

/// Whether the engine evaluates only what a frame invalidates.
///
/// The stack-lean resolve profile (`SWIFTTUI_STACK_LEAN_PROFILE=1`, the
/// default on WASI) evaluates the whole tree on every frame. The data a
/// body receives is the same under both profiles. What differs is which
/// other bodies run, so the expectations about that hold for the full
/// profile only.
@MainActor
var animatableProbeEvaluatesSelectively: Bool { !stackLeanResolveProfile }

@MainActor
final class AnimatableValueLog {
  var progress: Binding<Double>?
  var policy: Binding<AnimatableValueProbePolicy>?
  /// The data each evaluation of the site under test ran with, in order.
  var values: [Double] = []
  /// The same for a second site in the same view.
  var secondary: [Double] = []
  var evaluations: [String: Int] = [:]
  var completions = 0
  var appears = 0
  var disappears = 0

  func count(_ name: String) { evaluations[name, default: 0] += 1 }
}

/// A modifier that is both `@MainActor`, as every `ViewModifier` is, and
/// `Animatable`, which is nonisolated: `animatableData` is declared
/// `nonisolated`, and reads a `Sendable` stored property.
private struct ProgressFade: ViewModifier, Animatable {
  var progress: Double
  let log: AnimatableValueLog

  nonisolated var animatableData: Double {
    get { progress }
    set { progress = newValue }
  }

  func body(content: Content) -> some View {
    let _ = log.values.append(progress)
    // Never fully transparent, so the content can be read and clicked.
    content.opacity(0.25 + 0.75 * max(0, min(1, progress)))
  }
}

/// `ProgressFade` without the conformance.
private struct PlainProgressFade: ViewModifier {
  var progress: Double
  let log: AnimatableValueLog

  func body(content: Content) -> some View {
    let _ = log.values.append(progress)
    // Never fully transparent, so the content can be read and clicked.
    content.opacity(0.25 + 0.75 * max(0, min(1, progress)))
  }
}

private struct LevelGauge: View, Animatable {
  var level: Double
  let log: AnimatableValueLog
  var secondary = false

  nonisolated var animatableData: Double {
    get { level }
    set { level = newValue }
  }

  var body: some View {
    let _ = secondary ? log.secondary.append(level) : log.values.append(level)
    Text(String(repeating: "#", count: max(0, min(10, Int((level * 10).rounded())))))
  }
}

/// A view whose body root is a conditional.
private struct BranchingGauge: View, Animatable {
  var level: Double
  let log: AnimatableValueLog

  nonisolated var animatableData: Double {
    get { level }
    set { level = newValue }
  }

  var body: some View {
    let _ = log.values.append(level)
    if level >= 0 {
      Text("level \(Int((level * 100).rounded()))")
    } else {
      Text("below")
    }
  }
}

/// A view whose body root is a lone `Group`.
private struct GroupedGauge: View, Animatable {
  var level: Double
  let log: AnimatableValueLog

  nonisolated var animatableData: Double {
    get { level }
    set { level = newValue }
  }

  var body: some View {
    let _ = log.values.append(level)
    Group {
      Text("level \(Int((level * 100).rounded()))")
    }
  }
}

/// A conformer with nothing to animate.
private struct EmptyDataBadge: ViewModifier, Animatable {
  var label: String
  let log: AnimatableValueLog

  nonisolated var animatableData: EmptyAnimatableData {
    get { EmptyAnimatableData() }
    set {}
  }

  func body(content: Content) -> some View {
    let _ = log.count("badge")
    HStack(spacing: 1) {
      content
      Text(label)
    }
  }
}

private struct HostedCounter: View {
  @State private var count = 0
  let log: AnimatableValueLog

  var body: some View {
    Button("count \(count)") { count += 1 }
      .onAppear { log.appears += 1 }
      .onDisappear { log.disappears += 1 }
  }
}

private struct BesideOwner: View {
  let log: AnimatableValueLog

  var body: some View {
    let _ = log.count("sibling")
    HStack(spacing: 1) {
      Text("beside")
      ApartFromOwner(log: log)
    }
  }
}

private struct ApartFromOwner: View {
  let log: AnimatableValueLog

  var body: some View {
    let _ = log.count("unrelated")
    Text("apart")
  }
}

private enum ValueSnapMode: CaseIterable, CustomStringConvertible {
  case plainWrite, nilAnimation, disabledTransaction, reduceMotion, stableOutput

  var policy: AnimatableValueProbePolicy {
    switch self {
    case .reduceMotion: .reduceMotion
    case .stableOutput: .stableOutput
    case .plainWrite, .nilAnimation, .disabledTransaction: .normal
    }
  }

  var description: String {
    switch self {
    case .plainWrite: "plain-write"
    case .nilAnimation: "nil-animation"
    case .disabledTransaction: "disabled-transaction"
    case .reduceMotion: "reduce-motion"
    case .stableOutput: "stable-output"
    }
  }
}

// MARK: - Frames at fixed instants

/// Renders one modifier through a renderer of its own at fixed instants: the
/// frame at the first offset writes the new value under a linear 800 ms
/// transaction, and the later ones are ticks.
@MainActor
enum AnimatableValueFrames {
  static let proposal = ProposedSize(width: .finite(24), height: .finite(3))
  private static let animation = Animation.linear(duration: .milliseconds(800))

  static func run(named name: String, at offsets: [Int]) -> [Double] {
    let log = AnimatableValueLog()
    let renderer = DefaultRenderer()
    let controller = renderer.internalAnimationController
    let root = testIdentity("animatable-value", "frames", name)
    let start = MonotonicInstant(offset: .seconds(100))
    return withAnimationSinks(controller) {
      controller.register(animation)
      _ = renderer.renderArtifacts(
        view(0, log), context: .init(identity: root), proposal: proposal, frameInstant: start)
      return offsets.map { offset in
        _ = renderer.renderArtifacts(
          view(1, log),
          context: .init(identity: root, transaction: transaction(first: offset == offsets[0])),
          proposal: proposal, frameInstant: start.advanced(by: .milliseconds(offset)))
        return log.values.last ?? -1
      }
    }
  }

  static func runAsync(named name: String, at offsets: [Int]) async -> [Double] {
    let log = AnimatableValueLog()
    let renderer = DefaultRenderer()
    let controller = renderer.internalAnimationController
    let root = testIdentity("animatable-value", "frames", name)
    let start = MonotonicInstant(offset: .seconds(100))
    return await withAnimationSinks(controller) {
      controller.register(animation)
      _ = await renderer.renderArtifactsAsync(
        view(0, log), context: .init(identity: root), proposal: proposal, frameInstant: start)
      var values: [Double] = []
      for offset in offsets {
        _ = await renderer.renderArtifactsAsync(
          view(1, log),
          context: .init(identity: root, transaction: transaction(first: offset == offsets[0])),
          proposal: proposal, frameInstant: start.advanced(by: .milliseconds(offset)))
        values.append(log.values.last ?? -1)
      }
      return values
    }
  }

  private static func view(_ progress: Double, _ log: AnimatableValueLog) -> some View {
    Text("PRESENT").modifier(ProgressFade(progress: progress, log: log))
  }

  private static func transaction(first: Bool) -> TransactionSnapshot {
    var transaction = TransactionSnapshot()
    if first {
      transaction.animationRequest = .animate(animation.animationBox)
    }
    return transaction
  }
}

// MARK: - Run-loop probe

@MainActor
final class AnimatableValueProbeClock { var now = MonotonicInstant.now() }

enum AnimatableValueProbePolicy: Sendable {
  case normal, reduceMotion, stableOutput
}

/// What one frame of a probe did.
struct AnimatableValueFrame {
  /// Milliseconds since the frame of the state write.
  var milliseconds: Int
  /// The data the site under test was evaluated with during the frame.
  var values: [Double]
  var secondary: [Double]
  var frame: String
  /// Property animations in flight after the frame.
  var propertyAnimations: Int
  /// Animations of any kind in flight after the frame.
  var animationKeys: Int
  /// Completions that had fired by the end of the frame.
  var completions: Int

  /// One row of the frame without its trailing spaces.
  func line(_ row: Int) -> String {
    let rows = frame.split(separator: "\n", omittingEmptySubsequences: false)
    guard rows.indices.contains(row) else { return "" }
    return String(rows[row].reversed().drop { $0 == " " }.reversed())
  }
}

/// A run-loop harness around one view that depends on a `Double` state,
/// driven on an injected frame clock.
@MainActor
final class AnimatableValueProbe<Content: View> {
  let harness: StressRuntimeHarness<AnimatableValueProbeRoot<Content>>
  let clock: AnimatableValueProbeClock
  let log: AnimatableValueLog
  private var origin: MonotonicInstant

  init(
    named name: String,
    size: CellSize = .init(width: 30, height: 6),
    initial: Double = 0,
    policy: AnimatableValueProbePolicy = .normal,
    showsSibling: Bool = true,
    log: AnimatableValueLog = AnimatableValueLog(),
    @ViewBuilder content: @escaping (Double, AnimatableValueLog) -> Content
  ) throws {
    self.log = log
    harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("animatable-value", name),
      size: size
    ) {
      AnimatableValueProbeRoot(
        initial: initial, policy: policy, showsSibling: showsSibling, log: log, content: content)
    }
    // The clock starts after the mount frame: a frame never runs earlier
    // than the frame before it.
    let clock = AnimatableValueProbeClock()
    self.clock = clock
    origin = clock.now
    harness.runLoop.frameClock = { clock.now }
  }

  var controller: AnimationController {
    harness.runLoop.renderer.internalAnimationController
  }

  var frame: String { harness.frame }

  func shutdown() { harness.shutdown() }

  /// Runs `body` with the animation sinks bound, passing the start instant.
  func run(_ body: (MonotonicInstant) throws -> Void) throws {
    try withAnimationSinks(controller) { try body(clock.now) }
  }

  /// Writes the state and renders the frame of the write. `animation: nil`
  /// is a plain write, or `withAnimation(nil)` when `disabling`. With
  /// `atNextWake` the clock first moves to the next armed wake, so the write
  /// lands on a frame of the animation's own cadence.
  @discardableResult
  func set(
    _ target: Double,
    animation: Animation?,
    disabling: Bool = false,
    atNextWake: Bool = false
  ) throws -> AnimatableValueFrame {
    if atNextWake {
      clock.now = try #require(harness.runLoop.scheduler.nextWakeInstant(after: clock.now))
    } else {
      origin = clock.now
    }
    let progress = try #require(log.progress)
    let log = log
    let before = (log.values.count, log.secondary.count)
    if let animation {
      withAnimation(animation, completionCriteria: .logicallyComplete) {
        progress.wrappedValue = target
      } completion: {
        log.completions += 1
      }
    } else if disabling {
      withAnimation(nil) { progress.wrappedValue = target }
    } else {
      progress.wrappedValue = target
    }
    _ = try harness.render()
    return record(since: before)
  }

  /// Turns a rendering policy on at the next armed wake and renders that
  /// frame.
  func switchPolicy(to policy: AnimatableValueProbePolicy) throws -> AnimatableValueFrame {
    clock.now = try #require(harness.runLoop.scheduler.nextWakeInstant(after: clock.now))
    let binding = try #require(log.policy)
    let before = (log.values.count, log.secondary.count)
    binding.wrappedValue = policy
    _ = try harness.render()
    return record(since: before)
  }

  /// Renders the next armed wake, or returns `nil` when none is armed.
  func step() throws -> AnimatableValueFrame? {
    guard let wake = harness.runLoop.scheduler.nextWakeInstant(after: clock.now) else {
      return nil
    }
    let before = (log.values.count, log.secondary.count)
    clock.now = wake
    _ = try harness.render()
    return record(since: before)
  }

  /// Renders every armed wake until the scheduler has none left.
  func runToEnd(maxTurns: Int = 256) throws -> [AnimatableValueFrame] {
    var frames: [AnimatableValueFrame] = []
    while frames.count < maxTurns, let frame = try step() {
      frames.append(frame)
    }
    #expect(frames.count < maxTurns, "the animation must end within the turn budget")
    return frames
  }

  /// Renders the next armed wakes, `count` at most. It stops when the
  /// scheduler has none left.
  func steps(_ count: Int) throws -> [AnimatableValueFrame] {
    var frames: [AnimatableValueFrame] = []
    for _ in 0..<count {
      guard let frame = try step() else { break }
      frames.append(frame)
    }
    return frames
  }

  /// Renders `count` frames the test asks for, 33 ms apart, the first one
  /// 33 ms after the current instant, and returns them.
  ///
  /// A scene at rest has no frame armed, so ``steps(_:)`` and
  /// ``runToEnd(maxTurns:)`` render nothing there. A test that pins what a
  /// frame at rest does, or does not do, asks for the frames with this.
  func framesAtRest(_ count: Int) throws -> [AnimatableValueFrame] {
    var frames: [AnimatableValueFrame] = []
    for _ in 0..<count {
      let before = (log.values.count, log.secondary.count)
      clock.now = clock.now.advanced(by: .milliseconds(33))
      harness.runLoop.scheduler.requestDeadline(clock.now)
      _ = try harness.render()
      frames.append(record(since: before))
    }
    return frames
  }

  /// Renders `count` frames, 33 ms apart: the armed wakes while the
  /// scheduler has one, and then frames at rest that this asks for.
  ///
  /// For a test that pins what happens after an animation has ended, on
  /// frames the animation no longer arms.
  func frames(_ count: Int) throws -> [AnimatableValueFrame] {
    let armed = try steps(count)
    return armed + (try framesAtRest(count - armed.count))
  }

  /// Renders every armed wake before `milliseconds` after the last write,
  /// then one frame exactly there, and returns that frame with the values
  /// of every frame rendered on the way.
  func advance(toMilliseconds milliseconds: Int) throws -> AnimatableValueFrame {
    let target = origin.advanced(by: .milliseconds(milliseconds))
    let before = (log.values.count, log.secondary.count)
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
    return record(since: before)
  }

  /// Writes the state and runs to the end: the frame of the write first.
  func animate(to target: Double, _ animation: Animation?) throws -> [AnimatableValueFrame] {
    let first = try set(target, animation: animation)
    return [first] + (try runToEnd())
  }

  private func record(since before: (Int, Int)) -> AnimatableValueFrame {
    let state = controller.debugStateSnapshot()
    let elapsed = origin.duration(to: clock.now)
    return AnimatableValueFrame(
      milliseconds: Int(elapsed.components.seconds) * 1000
        + Int(elapsed.components.attoseconds / 1_000_000_000_000_000),
      values: Array(log.values[before.0...]),
      secondary: Array(log.secondary[before.1...]),
      frame: harness.frame,
      propertyAnimations: controller.activeAnimationCount,
      animationKeys: state.activeAnimationKeys.count,
      completions: log.completions
    )
  }
}

struct AnimatableValueProbeRoot<Content: View>: View {
  @State private var progress: Double
  @State private var policy: AnimatableValueProbePolicy
  /// Whether the view under test has a view below it. A view that departs
  /// under a transition is drawn where it was, over what moved up.
  let showsSibling: Bool
  let log: AnimatableValueLog
  let content: (Double, AnimatableValueLog) -> Content

  init(
    initial: Double,
    policy: AnimatableValueProbePolicy,
    showsSibling: Bool,
    log: AnimatableValueLog,
    content: @escaping (Double, AnimatableValueLog) -> Content
  ) {
    _progress = State(initialValue: initial)
    _policy = State(initialValue: policy)
    self.showsSibling = showsSibling
    self.log = log
    self.content = content
  }

  var body: some View {
    let _ = capture()
    VStack(alignment: .leading, spacing: 0) {
      content(progress, log)
      if showsSibling {
        BesideOwner(log: log)
      }
    }
    .environment(\.accessibilityReduceMotion, policy == .reduceMotion)
    .environment(\.stableOutput, policy == .stableOutput)
  }

  private func capture() {
    log.progress = $progress
    log.policy = $policy
    log.count("root")
  }
}
