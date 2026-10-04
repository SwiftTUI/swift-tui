import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIGraph
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite
struct AnimationEpicLifecycleTests {
  @MainActor
  private final class Probe {
    var events: [String] = []
    var values: [Double] = []
  }

  @Test("no-write completion scopes finish after the body without a frame")
  func noWriteScopesFinish() {
    let controller = AnimationController()
    let probe = Probe()
    AnimationCompletionStorage.withSink(controller) {
      withAnimation(.linear(duration: .seconds(10))) {
        probe.events.append("body")
      } completion: {
        probe.events.append("completion")
      }
      var transaction = Transaction()
      transaction.addAnimationCompletion { probe.events.append("logical") }
      transaction.addAnimationCompletion(criteria: .removed) { probe.events.append("removed") }
      withTransaction(transaction) {}
    }
    #expect(probe.events == ["body", "completion", "logical", "removed"])
    #expect(controller.debugStateSnapshot().completionClosureBatchIDs.isEmpty)
    #expect(!controller.frameDropEligibilityBlockers.contains(.animationCompletion))
  }

  @Test("no-write completion fires through an idle RunLoop input action")
  func noWriteCompletionThroughInput() throws {
    let probe = Probe()
    let harness = try AnimatorRuntimeHarness {
      Button("finish") {
        withAnimation(.linear(duration: .seconds(10))) {
        } completion: {
          probe.events.append("finished")
        }
      }
    }
    defer { harness.shutdown() }
    try withAnimationSinks(harness.runLoop.renderer.internalAnimationController) {
      _ = try harness.clickText("finish")
    }
    #expect(probe.events == ["finished"])
  }

  @Test("empty nested scopes do not prematurely complete a submitted outer batch")
  func nestedScopesKeepSeparateOwnership() {
    let controller = AnimationController()
    let scheduler = FrameScheduler()
    let state = StateContainer(initialState: 0)
    state.invalidator = scheduler
    let probe = Probe()
    withAnimationSinks(controller) {
      withAnimation(.linear(duration: .seconds(1))) {
        state.replace(with: 1)
        withAnimation(.linear(duration: .seconds(1))) {
        } completion: {
          probe.events.append("inner")
        }
      } completion: {
        probe.events.append("outer")
      }
    }
    #expect(probe.events == ["inner"])
    #expect(controller.debugStateSnapshot().completionClosureBatchIDs.count == 1)
    #expect(scheduler.hasPendingFrame())
  }

  @Test("empty completions respect frame-head rollback and commit")
  func emptyCompletionFrameTransaction() {
    let controller = AnimationController()
    let probe = Probe()
    func author() {
      AnimationCompletionStorage.withSink(controller) {
        withAnimation(nil) {
        } completion: {
          probe.events.append("finished")
        }
      }
    }
    let discarded = controller.beginFrameHeadTransaction()
    author()
    #expect(probe.events.isEmpty)
    controller.abortFrameHeadTransaction(discarded)
    #expect(probe.events.isEmpty)
    let committed = controller.beginFrameHeadTransaction()
    author()
    #expect(probe.events.isEmpty)
    controller.commitFrameHeadTransaction(committed)
    #expect(probe.events == ["finished"])
  }

  @Test("a throwing no-write scope completes and leaves no unclaimed batch")
  func throwingEmptyScope() {
    enum Failure: Error { case expected }
    let controller = AnimationController()
    let probe = Probe()
    do {
      try AnimationCompletionStorage.withSink(controller) {
        try withAnimation(nil) {
          throw Failure.expected
        } completion: {
          probe.events.append("finished")
        }
      }
      Issue.record("expected the body to throw")
    } catch {}
    #expect(probe.events == ["finished"])
    #expect(controller.debugStateSnapshot().unclaimedCompletionBatchIDs.isEmpty)
  }

  @Test("pruning the last logical retainer preserves a surviving batch's completion")
  func partialRetainerCompletion() {
    let controller = AnimationController()
    let early = Animation.linear(duration: .seconds(1)).logicallyComplete(after: .milliseconds(100))
    let late = Animation.linear(duration: .seconds(1)).logicallyComplete(after: .milliseconds(900))
    controller.register(early)
    controller.register(late)
    let batch = AnimationBatchID(92_001)
    let probe = Probe()
    controller.registerCompletion(batchID: batch) { probe.events.append("logical") }
    controller.registerCompletion(batchID: batch, barrier: .removed) {
      probe.events.append("removed")
    }
    let t0 = MonotonicInstant(offset: .seconds(100))
    func tree(opacity: Double, includesLate: Bool) -> ResolvedNode {
      func leaf(_ label: String, animation: Animation) -> ResolvedNode {
        var metadata = DrawMetadata()
        metadata.baseStyle.explicitOpacity = opacity
        var transaction = TransactionSnapshot()
        transaction.animationRequest = .animate(animation.animationBox)
        transaction.animationBatchID = batch
        return ResolvedNode(
          identity: testIdentity("partial", label), kind: .view("Leaf"),
          transactionSnapshot: transaction, drawMetadata: metadata)
      }
      return ResolvedNode(
        identity: testIdentity("partial"), kind: .view("Root"),
        children: [leaf("early", animation: early)]
          + (includesLate ? [leaf("late", animation: late)] : []))
    }
    controller.processResolvedTree(
      tree(opacity: 1, includesLate: true), transaction: .init(), timestamp: t0)
    var current = tree(opacity: 0, includesLate: true)
    controller.processResolvedTree(current, transaction: .init(), timestamp: t0)
    _ = controller.applyInterpolations(to: &current, at: t0.advanced(by: .milliseconds(200)))
    #expect(probe.events.isEmpty)
    current = tree(opacity: 0, includesLate: false)
    controller.processResolvedTree(
      current, transaction: .init(), timestamp: t0.advanced(by: .milliseconds(200)))
    #expect(probe.events == ["logical"])
    _ = controller.applyInterpolations(to: &current, at: t0.advanced(by: .seconds(2)))
    #expect(probe.events == ["logical", "removed"])
    #expect(controller.debugStateSnapshot().completionClosureBatchIDs.isEmpty)
  }

  @Test("reset clears previous-frame adoption offsets")
  func resetClearsAdoption() {
    var state = AnimationController.PreviousFrameState()
    let identity = testIdentity("adopted")
    state.adoptionOffsets[identity] = .init(identity: identity, dx: 4, dy: 2)
    state.reset()
    #expect(state.adoptionOffsets.isEmpty)
  }

  @Test("a motion-policy flip settles the original triggered keyframe endpoint")
  func keyframeMotionFlip() async throws {
    let probe = Probe()
    let harness = try AnimatorRuntimeHarness { KeyframeFixture(probe: probe) }
    defer { harness.shutdown() }
    try harness.clickText("bump")
    try await harness.wait(until: { (probe.values.last ?? 0) >= 2 })
    #expect((probe.values.last ?? 10) < 10)
    try harness.clickText("flip")
    try await harness.wait(until: { probe.values.last == 10 })
    try harness.clickText("flip")
    #expect(probe.values.last == 10)
    try harness.clickText("bump")
    try await harness.wait(until: { probe.values.last == 20 })
  }

  @Test("a phase motion-policy flip consumes reduced triggers and stays at rest")
  func phaseMotionFlip() async throws {
    let probe = Probe()
    let harness = try AnimatorRuntimeHarness { PhaseFixture(probe: probe) }
    defer { harness.shutdown() }
    try harness.clickText("bump")
    try await harness.wait(until: { probe.values.last == 1 })
    try harness.clickText("flip")
    try await harness.wait(until: { probe.values.last == 0 })
    try harness.clickText("bump")
    // Observe a bounded quiet window: a finished task does not request another
    // frame, so scheduler-based waits cannot use activeTaskCount as a signal.
    try await harness.hold(for: .milliseconds(100))
    try harness.clickText("flip")
    try await harness.hold(for: .milliseconds(100))
    #expect(probe.values.last == 0)
    let count = probe.values.count
    try harness.clickText("bump")
    try await harness.wait(until: { probe.values.dropFirst(count).contains(1) })
  }

  @Test(
    "a live reduced-motion toggle settles properties and exits with one completion",
    arguments: ["property", "implicit", "content", "matched", "insertion", "removal"])
  func liveMotionSettlesAnimation(family: String) throws {
    let probe = Probe()
    let harness = try AnimatorRuntimeHarness(size: .init(width: 50, height: 8)) {
      LiveMotionFixture(probe: probe, family: family)
    }
    defer { harness.shutdown() }
    let now = MonotonicInstant.now()
    harness.runLoop.frameClock = { now }
    let controller = harness.runLoop.renderer.internalAnimationController
    try withAnimationSinks(controller) { _ = try harness.clickText("start") }
    #expect(
      controller.activeAnimationCount > 0
        || !controller.debugStateSnapshot().removingIdentities.isEmpty)
    #expect(probe.events.isEmpty)
    try withAnimationSinks(controller) { _ = try harness.clickText("reduce") }
    #expect(controller.debugStateSnapshot().activeAnimationKeys.isEmpty)
    #expect(controller.debugStateSnapshot().removingIdentities.isEmpty)
    #expect(probe.events == ["finished"])
    #expect(harness.frame.contains("TARGET") == (family != "removal"))
    try withAnimationSinks(controller) { _ = try harness.clickText("reduce") }
    #expect(controller.debugStateSnapshot().activeAnimationKeys.isEmpty)
    #expect(probe.events == ["finished"])
  }

  private struct LiveMotionFixture: View {
    let probe: Probe
    let family: String
    @State private var moved = false
    @State private var reduced = false
    var body: some View {
      VStack(alignment: .leading) {
        HStack {
          Button("start") {
            withAnimation(.linear(duration: .seconds(30))) {
              moved = true
            } completion: {
              probe.events.append("finished")
            }
          }
          Button("reduce") { reduced.toggle() }
        }
        if family == "content" {
          Text(moved ? "TARGET200" : "TARGET100").contentTransition(.numericText())
        } else if family == "matched" {
          if moved {
            HStack {
              Text("other")
              Text("TARGET").matchedGeometryEffect(id: "hero")
            }
          } else {
            HStack {
              Text("TARGET").matchedGeometryEffect(id: "hero")
              Text("other")
            }
          }
        } else if family == "implicit" {
          Text("TARGET").offset(x: moved ? 12 : 0)
            .animation(.linear(duration: .seconds(30)), value: moved)
        } else if (family != "removal" || !moved) && (family != "insertion" || moved) {
          Text("TARGET").frame(width: moved ? 30 : 10, alignment: .leading)
        }
      }
      .environment(\.accessibilityReduceMotion, reduced)
    }
  }

  @Test("animation timelines stop live and resume without replaying missed ticks")
  func liveTimelineMotion() async throws {
    let probe = Probe()
    let harness = try AnimatorRuntimeHarness { TimelineMotionFixture(probe: probe) }
    defer { harness.shutdown() }
    try await harness.wait { probe.values.count >= 3 }
    try harness.clickText("reduce")
    let count = probe.values.count
    let pose = probe.values.last
    try await harness.hold(for: .milliseconds(350))
    #expect(probe.values.count == count)
    #expect(probe.values.last == pose)
    try harness.clickText("reduce")
    try await harness.wait { probe.values.count > count }
    #expect((probe.values.last ?? 0) > (pose ?? 0))
  }

  private struct TimelineMotionFixture: View {
    let probe: Probe
    @State private var reduced = false
    var body: some View {
      VStack {
        Button("reduce") { reduced.toggle() }
        TimelineView(.animation(minimumInterval: .milliseconds(20))) { context in
          Text("timeline").onChange(of: context.instant) { _, instant in
            probe.values.append(
              Double(instant.offset.components.seconds)
                + Double(instant.offset.components.attoseconds) / 1e18)
          }
        }
      }
      .environment(\.accessibilityReduceMotion, reduced)
    }
  }

  private struct KeyframeFixture: View {
    let probe: Probe
    @State private var trigger = 0
    @State private var reduced = false
    var body: some View {
      VStack {
        Button("bump") { trigger += 1 }
        Button("flip") { reduced.toggle() }
        KeyframeAnimator(initialValue: 0.0, trigger: trigger) { value in
          let _ = probe.values.append(value)
          Text("value=\(Int(value))")
        } keyframes: { start in
          LinearKeyframe(start + 10, duration: .seconds(1))
        }
      }
      .environment(\.accessibilityReduceMotion, reduced)
    }
  }

  private struct PhaseFixture: View {
    let probe: Probe
    @State private var trigger = 0
    @State private var reduced = false
    var body: some View {
      VStack {
        Button("bump") { trigger += 1 }
        Button("flip") { reduced.toggle() }
        PhaseAnimator([0, 1, 2], trigger: trigger) { phase in
          let _ = probe.values.append(Double(phase))
          Text("phase=\(phase)")
        } animation: { _ in
          .linear(duration: .seconds(1))
        }
      }
      .environment(\.accessibilityReduceMotion, reduced)
    }
  }
}
