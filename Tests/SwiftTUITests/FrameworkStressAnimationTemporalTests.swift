import Foundation
import Synchronization
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("SwiftTUI animation and temporal stress behavior", .serialized)
struct FrameworkStressAnimationTemporalTests {}

// MARK: - Attempt 001: unchanged value-animation inheritance

extension FrameworkStressAnimationTemporalTests {
  @Test("stress animation temporal 001 unchanged value animation inherits outer intent")
  func animationTemporal001UnchangedValueAnimationInheritsOuterIntent() throws {
    // Hypothesis: retained value-animation bookkeeping can mistake every outer
    // transaction for a watched-value change and replace its animation intent.
    let renderer = DefaultRenderer()
    let controller = renderer.internalAnimationController
    let outerAnimation = Animation.linear(duration: .seconds(4))
    controller.register(outerAnimation)
    let identity = testIdentity("AnimationTemporal001", "Root")
    let proposal = ProposedSize(width: 36, height: 4)

    _ = renderer.render(
      animationTemporal001View(opacity: 0.1, watchedValue: 7),
      context: .init(identity: identity),
      proposal: proposal
    )

    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(outerAnimation.animationBox)
    for generation in 1...16 {
      let opacity = generation.isMultiple(of: 2) ? 0.2 : 0.8
      _ = renderer.render(
        animationTemporal001View(opacity: opacity, watchedValue: 7),
        context: .init(identity: identity, transaction: transaction),
        proposal: proposal
      )
      #expect(
        controller.activeAnimationCount == 1,
        "generation \(generation) should retain exactly one outer opacity animation"
      )
    }
  }
}

@MainActor
private func animationTemporal001View(opacity: Double, watchedValue: Int) -> some View {
  Text("animation temporal 001")
    .opacity(opacity)
    .animation(.easeInOut(duration: .milliseconds(80)), value: watchedValue)
}

// MARK: - Attempt 002: nil value-animation suppression lifetime

extension FrameworkStressAnimationTemporalTests {
  @Test("stress animation temporal 002 nil value animation suppresses only its watched change")
  func animationTemporal002NilAnimationSuppressesOnlyWatchedChange() throws {
    // Hypothesis: a `.animation(nil,value:)` change can leave `.disabled` in
    // retained transaction state and suppress later unrelated outer animations.
    let renderer = DefaultRenderer()
    let controller = renderer.internalAnimationController
    let outerAnimation = Animation.linear(duration: .seconds(4))
    controller.register(outerAnimation)
    let identity = testIdentity("AnimationTemporal002", "Root")
    let proposal = ProposedSize(width: 36, height: 4)

    _ = renderer.render(
      animationTemporal002View(opacity: 0.1, watchedValue: 0),
      context: .init(identity: identity),
      proposal: proposal
    )
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(outerAnimation.animationBox)

    _ = renderer.render(
      animationTemporal002View(opacity: 0.5, watchedValue: 1),
      context: .init(identity: identity, transaction: transaction),
      proposal: proposal
    )
    withKnownIssue(
      "`.animation(nil,value:)` does not suppress an inherited animation when its value changes"
    ) {
      #expect(controller.activeAnimationCount == 0)
    }

    _ = renderer.render(
      animationTemporal002View(opacity: 0.9, watchedValue: 1),
      context: .init(identity: identity, transaction: transaction),
      proposal: proposal
    )
    #expect(controller.activeAnimationCount == 1)
  }
}

@MainActor
private func animationTemporal002View(opacity: Double, watchedValue: Int) -> some View {
  Text("animation temporal 002")
    .opacity(opacity)
    .animation(nil, value: watchedValue)
}

// MARK: - Attempt 003: value-animation baseline through entity reorder

extension FrameworkStressAnimationTemporalTests {
  @Test("stress animation temporal 003 value animation baselines follow reordered entities")
  func animationTemporal003ValueBaselinesFollowReorderedEntities() throws {
    // Hypothesis: the silent previous-value slot can follow structural row
    // position instead of entity identity and animate unchanged reordered rows.
    let renderer = DefaultRenderer()
    let controller = renderer.internalAnimationController
    let identity = testIdentity("AnimationTemporal003", "Root")
    let proposal = ProposedSize(width: 40, height: 6)
    let initial = [
      AnimationTemporal003Row(id: "a", value: 1, opacity: 0.2),
      AnimationTemporal003Row(id: "b", value: 2, opacity: 0.7),
    ]

    _ = renderer.render(
      animationTemporal003View(rows: initial),
      context: .init(identity: identity),
      proposal: proposal
    )
    _ = renderer.render(
      animationTemporal003View(rows: Array(initial.reversed())),
      context: .init(identity: identity),
      proposal: proposal
    )
    #expect(controller.activeAnimationCount == 0)

    let changed = [
      AnimationTemporal003Row(id: "b", value: 2, opacity: 0.7),
      AnimationTemporal003Row(id: "a", value: 3, opacity: 0.9),
    ]
    _ = renderer.render(
      animationTemporal003View(rows: changed),
      context: .init(identity: identity),
      proposal: proposal
    )
    withKnownIssue("A reordered ForEach entity loses its value-animation baseline") {
      #expect(controller.activeAnimationCount == 1)
    }
  }
}

private struct AnimationTemporal003Row: Identifiable, Sendable {
  let id: String
  let value: Int
  let opacity: Double
}

@MainActor
private func animationTemporal003View(rows: [AnimationTemporal003Row]) -> some View {
  VStack(alignment: .leading, spacing: 0) {
    ForEach(rows) { row in
      Text("003 row \(row.id)")
        .opacity(row.opacity)
        .animation(.linear(duration: .seconds(4)), value: row.value)
    }
  }
}

// MARK: - Attempt 004: duplicate occurrence value-animation isolation

extension FrameworkStressAnimationTemporalTests {
  @Test("stress animation temporal 004 duplicate occurrences isolate value animation baselines")
  func animationTemporal004DuplicateOccurrencesIsolateValueBaselines() throws {
    // Hypothesis: duplicate entity routes can collapse their silent modifier
    // slots and make one occurrence consume the other's watched-value baseline.
    let renderer = DefaultRenderer()
    let controller = renderer.internalAnimationController
    let identity = testIdentity("AnimationTemporal004", "Root")
    let proposal = ProposedSize(width: 40, height: 6)

    _ = renderer.render(
      animationTemporal004View(firstValue: 1, firstOpacity: 0.2),
      context: .init(identity: identity),
      proposal: proposal
    )
    _ = renderer.render(
      animationTemporal004View(firstValue: 3, firstOpacity: 0.9),
      context: .init(identity: identity),
      proposal: proposal
    )

    withKnownIssue("Duplicate ForEach occurrences lose independent value-animation baselines") {
      #expect(controller.activeAnimationCount == 1)
    }
  }
}

@MainActor
private func animationTemporal004View(firstValue: Int, firstOpacity: Double) -> some View {
  let rows = [
    AnimationTemporal004Row(
      id: "duplicate", label: "first", value: firstValue, opacity: firstOpacity),
    AnimationTemporal004Row(id: "duplicate", label: "second", value: 2, opacity: 0.6),
  ]
  return VStack(alignment: .leading, spacing: 0) {
    ForEach(rows) { row in
      Text("004 \(row.label)")
        .opacity(row.opacity)
        .animation(.linear(duration: .seconds(4)), value: row.value)
    }
  }
}

private struct AnimationTemporal004Row: Identifiable, Sendable {
  let id: String
  let label: String
  let value: Int
  let opacity: Double
}

// MARK: - Attempt 005: explicit identity value-animation lifetime

extension FrameworkStressAnimationTemporalTests {
  @Test("stress animation temporal 005 explicit identity replacement starts a fresh baseline")
  func animationTemporal005ExplicitIdentityReplacementStartsFreshBaseline() throws {
    // Hypothesis: the modifier's reserved state slot can survive explicit ID
    // replacement and animate the new owner from its predecessor's value.
    let renderer = DefaultRenderer()
    let controller = renderer.internalAnimationController
    let identity = testIdentity("AnimationTemporal005", "Root")
    let proposal = ProposedSize(width: 40, height: 4)

    _ = renderer.render(
      animationTemporal005View(owner: "a", value: 1, opacity: 0.2),
      context: .init(identity: identity),
      proposal: proposal
    )
    _ = renderer.render(
      animationTemporal005View(owner: "b", value: 2, opacity: 0.8),
      context: .init(identity: identity),
      proposal: proposal
    )
    #expect(controller.activeAnimationCount == 0)

    _ = renderer.render(
      animationTemporal005View(owner: "b", value: 3, opacity: 0.4),
      context: .init(identity: identity),
      proposal: proposal
    )
    withKnownIssue("A replacement owner does not establish a live value-animation baseline") {
      #expect(controller.activeAnimationCount == 1)
    }
  }
}

@MainActor
private func animationTemporal005View(owner: String, value: Int, opacity: Double) -> some View {
  Text("animation temporal 005")
    .opacity(opacity)
    .animation(.linear(duration: .seconds(4)), value: value)
    .id(owner)
}

// MARK: - Attempt 006: removed value-animation modifier intent

extension FrameworkStressAnimationTemporalTests {
  @Test("stress animation temporal 006 removed value animation leaves no stale intent")
  func animationTemporal006RemovedValueAnimationLeavesNoStaleIntent() throws {
    // Hypothesis: retained transaction state can preserve a departed
    // `.animation(nil,value:)` modifier and disable the stable payload later.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("AnimationTemporal006", "Root"),
      size: .init(width: 52, height: 8)
    ) {
      AnimationTemporal006View()
    }
    defer { harness.shutdown() }

    var missedGenerations: [Int] = []
    for generation in 1...8 {
      _ = try harness.clickText("Toggle Suppressor 006")
      _ = try harness.clickText("Animate Opacity 006")
      if harness.runLoop.renderer.internalAnimationController.activeAnimationCount != 1 {
        missedGenerations.append(generation)
      }
      _ = try harness.clickText("Toggle Suppressor 006")
      _ = try harness.clickText("Animate Opacity 006")
    }
    withKnownIssue("A departed value-animation modifier suppresses later outer animation") {
      #expect(missedGenerations.isEmpty)
    }
  }
}

@MainActor
private struct AnimationTemporal006View: View {
  @State private var opacity = 0.2
  @State private var suppresses = true

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Toggle Suppressor 006") { suppresses.toggle() }
      Button("Animate Opacity 006") {
        withAnimation(.linear(duration: .seconds(4))) {
          opacity = opacity < 0.5 ? 0.9 : 0.2
        }
      }
      if suppresses {
        Text("006 payload")
          .opacity(opacity)
          .animation(nil, value: opacity)
          .id("animation-temporal-006-payload")
      } else {
        Text("006 payload")
          .opacity(opacity)
          .id("animation-temporal-006-payload")
      }
    }
  }
}

// MARK: - Attempt 007: nested transaction suppressor removal

extension FrameworkStressAnimationTemporalTests {
  @Test("stress animation temporal 007 removing inner suppressor restores outer transaction")
  func animationTemporal007RemovingInnerSuppressorRestoresOuterTransaction() throws {
    // Hypothesis: retained transaction snapshots can keep the inner disabled
    // request after that modifier branch leaves the stable outer transaction.
    let renderer = DefaultRenderer()
    let animation = Animation.linear(duration: .seconds(4))
    renderer.internalAnimationController.register(animation)
    let identity = testIdentity("AnimationTemporal007", "Root")
    let proposal = ProposedSize(width: 40, height: 5)

    for generation in 0..<16 {
      let suppressed = generation.isMultiple(of: 2)
      let artifacts = renderer.render(
        animationTemporal007View(suppressed: suppressed, animation: animation),
        context: .init(identity: identity),
        proposal: proposal
      )
      let payload = try #require(
        animationTemporalDescendant(
          in: artifacts.resolvedTree,
          text: "animation temporal 007"
        )
      )
      if suppressed {
        #expect(payload.transactionSnapshot.animationRequest == .disabled)
      } else {
        #expect(payload.transactionSnapshot.animationRequest == .inherit)
      }
    }
  }
}

@MainActor
@ViewBuilder
private func animationTemporal007View(suppressed: Bool, animation: Animation) -> some View {
  VStack(alignment: .leading, spacing: 0) {
    if suppressed {
      Text("animation temporal 007")
        .transaction { $0.disablesAnimations = true }
        .id("animation-temporal-007-payload")
    } else {
      Text("animation temporal 007")
        .id("animation-temporal-007-payload")
    }
  }
  .transaction { $0.animation = animation }
}

private func animationTemporalDescendant(in node: ResolvedNode, text: String) -> ResolvedNode? {
  if case .text(let value) = node.drawPayload, value == text {
    return node
  }
  for child in node.children {
    if let match = animationTemporalDescendant(in: child, text: text) {
      return match
    }
  }
  return nil
}

// MARK: - Attempt 008: reduce-motion animation intent recovery

extension FrameworkStressAnimationTemporalTests {
  @Test("stress animation temporal 008 reduce motion disables and restores value animation")
  func animationTemporal008ReduceMotionDisablesAndRestoresValueAnimation() throws {
    // Hypothesis: the reduced-motion disabled transaction can become the
    // retained baseline and survive after accessibility policy is restored.
    let renderer = DefaultRenderer()
    let animation = Animation.linear(duration: .seconds(4))
    renderer.internalAnimationController.register(animation)
    let identity = testIdentity("AnimationTemporal008", "Root")
    let proposal = ProposedSize(width: 44, height: 4)

    _ = renderer.render(
      animationTemporal008View(value: 0, reducedMotion: false, animation: animation),
      context: .init(identity: identity),
      proposal: proposal
    )
    let reduced = renderer.render(
      animationTemporal008View(value: 1, reducedMotion: true, animation: animation),
      context: .init(identity: identity),
      proposal: proposal
    )
    let reducedPayload = try #require(
      animationTemporalDescendant(in: reduced.resolvedTree, text: "animation temporal 008")
    )
    withKnownIssue("Reduced motion does not disable a changed value-animation modifier") {
      #expect(reducedPayload.transactionSnapshot.animationRequest == .disabled)
    }

    let restored = renderer.render(
      animationTemporal008View(value: 2, reducedMotion: false, animation: animation),
      context: .init(identity: identity),
      proposal: proposal
    )
    let restoredPayload = try #require(
      animationTemporalDescendant(in: restored.resolvedTree, text: "animation temporal 008")
    )
    withKnownIssue("Value-animation intent does not recover after reduce motion is disabled") {
      #expect(
        restoredPayload.transactionSnapshot.animationRequest == .animate(animation.animationBox))
    }
  }
}

@MainActor
private func animationTemporal008View(
  value: Int,
  reducedMotion: Bool,
  animation: Animation
) -> some View {
  Text("animation temporal 008")
    .opacity(value.isMultiple(of: 2) ? 0.2 : 0.8)
    .animation(animation, value: value)
    .environment(\.accessibilityReduceMotion, reducedMotion)
}

// MARK: - Attempt 009: completed animation registration retention

extension FrameworkStressAnimationTemporalTests {
  @Test("stress animation temporal 009 completed unique animations keep registration bounded")
  func animationTemporal009CompletedUniqueAnimationsKeepRegistrationBounded() throws {
    // Hypothesis: the controller's box-to-animation ledger never prunes unique
    // finite curves after their last active record completes.
    let controller = AnimationController()
    let identity = testIdentity("AnimationTemporal009", "Leaf")
    let start = MonotonicInstant(offset: .seconds(10))
    var baseline = animationTemporalNode(identity: identity, opacity: 0.1)
    controller.processResolvedTree(baseline, transaction: .init(), timestamp: start)

    for generation in 1...24 {
      let animation = Animation.linear(duration: .milliseconds(100 + generation))
      controller.register(animation)
      baseline = animationTemporalNode(
        identity: identity,
        opacity: generation.isMultiple(of: 2) ? 0.2 : 0.8
      )
      var transaction = TransactionSnapshot()
      transaction.animationRequest = .animate(animation.animationBox)
      let frameTime = start.advanced(by: .seconds(generation))
      controller.processResolvedTree(baseline, transaction: transaction, timestamp: frameTime)
      var tickTree = baseline
      _ = controller.applyInterpolations(
        to: &tickTree,
        at: frameTime.advanced(by: .seconds(1))
      )
      #expect(controller.activeAnimationCount == 0)
    }

    withKnownIssue("Completed unique animations remain in the controller registration ledger") {
      #expect(controller.debugStateSnapshot().registeredAnimationCount <= 2)
    }
  }
}

private func animationTemporalNode(
  identity: Identity,
  opacity: Double = 1,
  padding: EdgeInsets? = nil,
  viewNodeID: ViewNodeID? = nil,
  children: [ResolvedNode] = []
) -> ResolvedNode {
  var metadata = DrawMetadata()
  metadata.baseStyle.explicitOpacity = opacity
  return ResolvedNode(
    viewNodeID: viewNodeID,
    identity: identity,
    kind: .view("AnimationTemporalLeaf"),
    children: children,
    layoutBehavior: padding.map(LayoutBehavior.padding) ?? .intrinsic,
    drawMetadata: metadata
  )
}

// MARK: - Attempt 010: rapid property retarget convergence

extension FrameworkStressAnimationTemporalTests {
  @Test("stress animation temporal 010 rapid property retarget converges on latest target")
  func animationTemporal010RapidPropertyRetargetConvergesOnLatestTarget() throws {
    // Hypothesis: repeated sample-and-replace retargeting can retain parallel
    // records for one slot or complete against an earlier target.
    let controller = AnimationController()
    let animation = Animation.linear(duration: .seconds(2))
    controller.register(animation)
    let identity = testIdentity("AnimationTemporal010", "Leaf")
    let start = MonotonicInstant(offset: .seconds(20))
    controller.processResolvedTree(
      animationTemporalNode(identity: identity, opacity: 0),
      transaction: .init(),
      timestamp: start
    )
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    var latestTarget = 0.0

    for generation in 1...16 {
      latestTarget = Double(generation) / 20
      let node = animationTemporalNode(identity: identity, opacity: latestTarget)
      controller.processResolvedTree(
        node,
        transaction: transaction,
        timestamp: start.advanced(by: .milliseconds(generation * 20))
      )
      #expect(controller.activeAnimationCount == 1)
    }

    var finalTree = animationTemporalNode(identity: identity, opacity: latestTarget)
    _ = controller.applyInterpolations(
      to: &finalTree,
      at: start.advanced(by: .seconds(5))
    )
    #expect(controller.activeAnimationCount == 0)
    #expect(finalTree.drawMetadata.baseStyle.explicitOpacity == latestTarget)
  }
}

// MARK: - Attempt 011: custom-state continuity after retarget

extension FrameworkStressAnimationTemporalTests {
  @Test("stress animation temporal 011 custom state survives into retarget replacement")
  func animationTemporal011CustomStateSurvivesIntoRetargetReplacement() throws {
    // Hypothesis: retarget sampling reads the old custom state but the newly
    // installed ActiveAnimation silently starts with an empty state buffer.
    let probe = AnimationTemporalCustomStateProbe()
    let animation = Animation(AnimationTemporalStatefulCurve(id: "011", probe: probe))
    let controller = AnimationController()
    controller.register(animation)
    let identity = testIdentity("AnimationTemporal011", "Leaf")
    let start = MonotonicInstant(offset: .seconds(30))
    controller.processResolvedTree(
      animationTemporalNode(identity: identity, opacity: 0),
      transaction: .init(),
      timestamp: start
    )
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    var firstTarget = animationTemporalNode(identity: identity, opacity: 1)
    controller.processResolvedTree(firstTarget, transaction: transaction, timestamp: start)
    _ = controller.applyInterpolations(
      to: &firstTarget,
      at: start.advanced(by: .milliseconds(100))
    )

    let replacement = animationTemporalNode(identity: identity, opacity: 0.4)
    controller.processResolvedTree(
      replacement,
      transaction: transaction,
      timestamp: start.advanced(by: .milliseconds(200))
    )
    var replacementTick = replacement
    _ = controller.applyInterpolations(
      to: &replacementTick,
      at: start.advanced(by: .milliseconds(300))
    )

    withKnownIssue("Retarget replacement resets CustomAnimation state after sampling it") {
      #expect((probe.observations.last ?? -1) >= 2)
    }
  }
}

// MARK: - Attempt 012: custom merge consultation

extension FrameworkStressAnimationTemporalTests {
  @Test("stress animation temporal 012 retarget consults custom merge policy")
  func animationTemporal012RetargetConsultsCustomMergePolicy() throws {
    // Hypothesis: property retargeting replaces a custom curve without ever
    // consulting its public shouldMerge handoff policy.
    let probe = AnimationTemporalCustomStateProbe()
    let animation = Animation(AnimationTemporalStatefulCurve(id: "012", probe: probe))
    let controller = AnimationController()
    controller.register(animation)
    let identity = testIdentity("AnimationTemporal012", "Leaf")
    let start = MonotonicInstant(offset: .seconds(40))
    controller.processResolvedTree(
      animationTemporalNode(identity: identity, opacity: 0),
      transaction: .init(),
      timestamp: start
    )
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    controller.processResolvedTree(
      animationTemporalNode(identity: identity, opacity: 1),
      transaction: transaction,
      timestamp: start
    )
    controller.processResolvedTree(
      animationTemporalNode(identity: identity, opacity: 0.4),
      transaction: transaction,
      timestamp: start.advanced(by: .milliseconds(100))
    )

    withKnownIssue("AnimationController retargeting never calls CustomAnimation.shouldMerge") {
      #expect(probe.mergeCallCount > 0)
    }
  }
}

private final class AnimationTemporalCustomStateProbe: Sendable {
  private let storage = Mutex<[Int]>([])
  private let merges = Atomic<Int>(0)
  private let velocities = Atomic<Int>(0)

  var observations: [Int] {
    storage.withLock { $0 }
  }

  var mergeCallCount: Int {
    merges.load(ordering: .relaxed)
  }

  var velocityCallCount: Int {
    velocities.load(ordering: .relaxed)
  }

  func record(_ value: Int) {
    storage.withLock { $0.append(value) }
  }

  func recordMerge() {
    merges.wrappingAdd(1, ordering: .relaxed)
  }

  func recordVelocity() {
    velocities.wrappingAdd(1, ordering: .relaxed)
  }
}

private struct AnimationTemporalStatefulCurve: CustomAnimation {
  let id: String
  let probe: AnimationTemporalCustomStateProbe

  func animate<V: VectorArithmetic>(
    value: V,
    time: Duration,
    context: inout AnimationContext<V>
  ) -> V? {
    let count: Int = context.state["animation-temporal-state"] ?? 0
    probe.record(count)
    context.state["animation-temporal-state"] = count + 1
    guard time < .seconds(10) else { return nil }
    var result = value
    result.scale(by: min(max(time.totalSeconds / 10, 0), 1))
    return result
  }

  func shouldMerge<V: VectorArithmetic>(
    previous: Animation,
    value: V,
    time: Duration,
    context: inout AnimationContext<V>
  ) -> Bool {
    probe.recordMerge()
    return true
  }

  func velocity<V: VectorArithmetic>(
    value: V,
    time: Duration,
    context: AnimationContext<V>
  ) -> V? {
    probe.recordVelocity()
    return value
  }

  static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }

  func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Attempt 013: custom velocity handoff

extension FrameworkStressAnimationTemporalTests {
  @Test("stress animation temporal 013 interrupted retarget consults custom velocity")
  func animationTemporal013InterruptedRetargetConsultsCustomVelocity() throws {
    // Hypothesis: interruption samples visual progress but omits the custom
    // curve's velocity hook, losing momentum across the replacement.
    let probe = AnimationTemporalCustomStateProbe()
    let animation = Animation(AnimationTemporalStatefulCurve(id: "013", probe: probe))
    let controller = AnimationController()
    controller.register(animation)
    let identity = testIdentity("AnimationTemporal013", "Leaf")
    let start = MonotonicInstant(offset: .seconds(50))
    controller.processResolvedTree(
      animationTemporalNode(identity: identity, opacity: 0),
      transaction: .init(),
      timestamp: start
    )
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    controller.processResolvedTree(
      animationTemporalNode(identity: identity, opacity: 1),
      transaction: transaction,
      timestamp: start
    )
    controller.processResolvedTree(
      animationTemporalNode(identity: identity, opacity: 0.3),
      transaction: transaction,
      timestamp: start.advanced(by: .milliseconds(200))
    )

    withKnownIssue("AnimationController interruption never calls CustomAnimation.velocity") {
      #expect(probe.velocityCallCount > 0)
    }
  }
}

// MARK: - Attempt 014: independent custom state per property slot

extension FrameworkStressAnimationTemporalTests {
  @Test("stress animation temporal 014 custom state stays isolated across property slots")
  func animationTemporal014CustomStateStaysIsolatedAcrossPropertySlots() throws {
    // Hypothesis: two property records sharing one AnimationBox can also share
    // one mutable AnimationState and advance each other's custom bookkeeping.
    let probe = AnimationTemporalCustomStateProbe()
    let animation = Animation(AnimationTemporalStatefulCurve(id: "014", probe: probe))
    let controller = AnimationController()
    controller.register(animation)
    let identity = testIdentity("AnimationTemporal014", "Leaf")
    let start = MonotonicInstant(offset: .seconds(60))
    controller.processResolvedTree(
      animationTemporalNode(identity: identity, opacity: 0, padding: .zero),
      transaction: .init(),
      timestamp: start
    )
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    var target = animationTemporalNode(
      identity: identity,
      opacity: 1,
      padding: EdgeInsets(all: 8)
    )
    controller.processResolvedTree(target, transaction: transaction, timestamp: start)
    _ = controller.applyInterpolations(
      to: &target,
      at: start.advanced(by: .milliseconds(100))
    )
    #expect(Array(probe.observations.suffix(2)).sorted() == [0, 0])

    _ = controller.applyInterpolations(
      to: &target,
      at: start.advanced(by: .milliseconds(200))
    )
    #expect(Array(probe.observations.suffix(2)).sorted() == [1, 1])
  }
}

// MARK: - Attempt 015: insertion-offset custom sampling cadence

extension FrameworkStressAnimationTemporalTests {
  @Test("stress animation temporal 015 insertion offset custom curve samples once per frame")
  func animationTemporal015InsertionOffsetCustomCurveSamplesOncePerFrame() throws {
    // Hypothesis: the resolved animation pass and placed overlay pass can both
    // evaluate a stateful insertion curve during one frame.
    let renderer = DefaultRenderer()
    let controller = renderer.internalAnimationController
    let probe = AnimationTemporalCustomStateProbe()
    let animation = Animation(AnimationTemporalStatefulCurve(id: "015", probe: probe))
    controller.register(animation)
    let identity = testIdentity("AnimationTemporal015", "Root")
    let proposal = ProposedSize(width: 40, height: 6)

    withAnimationSinks(controller) {
      _ = renderer.render(
        animationTemporal015View(show: false),
        context: .init(identity: identity),
        proposal: proposal
      )
      var transaction = TransactionSnapshot()
      transaction.animationRequest = .animate(animation.animationBox)
      let inserted = renderer.render(
        animationTemporal015View(show: true),
        context: .init(identity: identity, transaction: transaction),
        proposal: proposal
      )
      #expect(controller.activeInsertionOffsetCount == 1)
      let callsBefore = probe.observations.count
      let sampleTime = MonotonicInstant.now()
      var resolved = inserted.resolvedTree
      _ = controller.applyInterpolations(to: &resolved, at: sampleTime)
      _ = controller.placedAnimationOverlaySnapshot(
        for: inserted.placedTree,
        at: sampleTime,
        surfaceSize: .init(width: 40, height: 6)
      )
      #expect(probe.observations.count - callsBefore == 1)
    }
  }
}

@MainActor
@ViewBuilder
private func animationTemporal015View(show: Bool) -> some View {
  VStack(alignment: .leading, spacing: 0) {
    if show {
      Text("animation temporal 015")
        .transition(.offset(x: 12))
    }
  }
}

// MARK: - Attempt 016: removal-overlay custom sampling cadence

extension FrameworkStressAnimationTemporalTests {
  @Test("stress animation temporal 016 removal custom curve samples once per frame")
  func animationTemporal016RemovalCustomCurveSamplesOncePerFrame() throws {
    // Hypothesis: a placed removal is sampled once while producing resolved
    // tick state and again while producing its placed overlay in the same frame.
    let renderer = DefaultRenderer()
    let controller = renderer.internalAnimationController
    let probe = AnimationTemporalCustomStateProbe()
    let animation = Animation(AnimationTemporalStatefulCurve(id: "016", probe: probe))
    controller.register(animation)
    let identity = testIdentity("AnimationTemporal016", "Root")
    let proposal = ProposedSize(width: 40, height: 6)

    withAnimationSinks(controller) {
      _ = renderer.render(
        animationTemporal016View(show: true),
        context: .init(identity: identity),
        proposal: proposal
      )
      var transaction = TransactionSnapshot()
      transaction.animationRequest = .animate(animation.animationBox)
      let removed = renderer.render(
        animationTemporal016View(show: false),
        context: .init(identity: identity, transaction: transaction),
        proposal: proposal
      )
      #expect(controller.debugStateSnapshot().removingIdentities.count == 1)
      let callsBefore = probe.observations.count
      let sampleTime = MonotonicInstant.now()
      var resolved = removed.resolvedTree
      _ = controller.applyInterpolations(to: &resolved, at: sampleTime)
      _ = controller.placedAnimationOverlaySnapshot(
        for: removed.placedTree,
        at: sampleTime,
        surfaceSize: .init(width: 40, height: 6)
      )
      withKnownIssue("Placed removal CustomAnimation is evaluated twice per frame") {
        #expect(probe.observations.count - callsBefore == 1)
      }
    }
  }
}

@MainActor
@ViewBuilder
private func animationTemporal016View(show: Bool) -> some View {
  VStack(alignment: .leading, spacing: 0) {
    if show {
      Text("animation temporal 016")
        .transition(.opacity.combined(with: .offset(x: 8)))
    }
  }
}

// MARK: - Attempt 017: reset versus in-flight frame draft

extension FrameworkStressAnimationTemporalTests {
  @Test("stress animation temporal 017 reset dominates an older frame draft commit")
  func animationTemporal017ResetDominatesOlderFrameDraftCommit() throws {
    // Hypothesis: reset has no generation barrier, so an already-created draft
    // can commit afterward and resurrect the controller's pre-reset ledger.
    let controller = AnimationController()
    controller.register(.linear(duration: .seconds(3)))
    let draft = controller.makeFrameDraft()

    controller.reset()
    #expect(controller.debugStateSnapshot().registeredAnimationCount == 0)
    draft.commit()

    withKnownIssue("An in-flight AnimationFrameDraft commit resurrects state after reset") {
      #expect(controller.debugStateSnapshot().registeredAnimationCount == 0)
    }
  }
}

// MARK: - Attempt 018: partial multi-slot batch supersession

extension FrameworkStressAnimationTemporalTests {
  @Test("stress animation temporal 018 completion waits for surviving slot after supersession")
  func animationTemporal018CompletionWaitsForSurvivingSlotAfterSupersession() throws {
    // Hypothesis: superseding one record can release the shared batch as if all
    // of its independently animated property slots had drained.
    let controller = AnimationController()
    let animation = Animation.linear(duration: .milliseconds(500))
    controller.register(animation)
    let identity = testIdentity("AnimationTemporal018", "Leaf")
    let batch = AnimationBatchID(18)
    let fired = Atomic<Int>(0)
    controller.registerCompletion(batchID: batch) {
      fired.wrappingAdd(1, ordering: .relaxed)
    }
    let start = MonotonicInstant(offset: .seconds(70))
    controller.processResolvedTree(
      animationTemporalNode(identity: identity, opacity: 0, padding: .zero),
      transaction: .init(),
      timestamp: start
    )
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    transaction.animationBatchID = batch
    let target = animationTemporalNode(
      identity: identity,
      opacity: 1,
      padding: EdgeInsets(all: 6)
    )
    controller.processResolvedTree(target, transaction: transaction, timestamp: start)
    #expect(controller.activeAnimationCount == 2)

    let superseding = animationTemporalNode(
      identity: identity,
      opacity: 0.4,
      padding: EdgeInsets(all: 6)
    )
    var disabled = TransactionSnapshot()
    disabled.animationRequest = .disabled
    controller.processResolvedTree(
      superseding,
      transaction: disabled,
      timestamp: start.advanced(by: .milliseconds(100))
    )
    #expect(fired.load(ordering: .relaxed) == 0)
    #expect(controller.activeAnimationCount == 1)

    var finalTree = superseding
    _ = controller.applyInterpolations(
      to: &finalTree,
      at: start.advanced(by: .seconds(1))
    )
    #expect(fired.load(ordering: .relaxed) == 1)
    #expect(controller.activeAnimationCount == 0)
  }
}

private func animationTemporalRoot(
  identity: Identity,
  children: [ResolvedNode] = []
) -> ResolvedNode {
  ResolvedNode(identity: identity, kind: .view("AnimationTemporalRoot"), children: children)
}

private func animationTemporalContainsOffset(in node: ResolvedNode) -> Bool {
  if case .offset = node.layoutBehavior {
    return true
  }
  return node.children.contains { animationTemporalContainsOffset(in: $0) }
}

private func animationTemporalMatchedNode(
  identity: Identity,
  nodeID: UInt64,
  key: MatchedGeometryKey
) -> ResolvedNode {
  var node = animationTemporalNode(
    identity: identity,
    viewNodeID: ViewNodeID(rawValue: nodeID)
  )
  node.matchedGeometry = MatchedGeometryConfig(key: key)
  return node
}

private func animationTemporalPlacedRoot(
  identity: Identity,
  children: [PlacedNode]
) -> PlacedNode {
  PlacedNode(
    identity: identity,
    bounds: CellRect(origin: CellPoint(x: 0, y: 0), size: CellSize(width: 80, height: 8)),
    children: children
  )
}

private func animationTemporalPlacedMatchedNode(
  identity: Identity,
  key: MatchedGeometryKey,
  x: Int
) -> PlacedNode {
  PlacedNode(
    identity: identity,
    bounds: CellRect(origin: CellPoint(x: x, y: 0), size: CellSize(width: 8, height: 1)),
    matchedGeometry: MatchedGeometryConfig(key: key)
  )
}

// MARK: - Attempt 019: departed transition registration

extension FrameworkStressAnimationTemporalTests {
  @Test("stress animation temporal 019 removed transition modifier cannot animate later removal")
  func animationTemporal019RemovedTransitionCannotAnimateLaterRemoval() throws {
    // Hypothesis: transition collection merges pending registrations without
    // deleting a live node's departed modifier, so a later removal reuses it.
    let controller = AnimationController()
    let animation = Animation.linear(duration: .seconds(1))
    controller.register(animation)
    let rootID = testIdentity("AnimationTemporal019", "Root")
    let leafID = testIdentity("AnimationTemporal019", "Leaf")
    let nodeID = ViewNodeID(rawValue: 19)
    let start = MonotonicInstant(offset: .seconds(80))
    let leaf = animationTemporalNode(identity: leafID, viewNodeID: nodeID)

    controller.beginTransitionCollection()
    controller.registerTransition(
      for: leafID, viewNodeID: nodeID, transition: AnyTransition.opacity)
    controller.finishTransitionCollection()
    controller.processResolvedTree(
      animationTemporalRoot(identity: rootID, children: [leaf]),
      transaction: .init(),
      timestamp: start
    )

    controller.beginTransitionCollection()
    controller.finishTransitionCollection()
    controller.processResolvedTree(
      animationTemporalRoot(identity: rootID, children: [leaf]),
      transaction: .init(),
      timestamp: start.advanced(by: .milliseconds(20))
    )
    withKnownIssue("A removed transition modifier remains registered on its live node") {
      #expect(controller.debugStateSnapshot().transitionNodeIDs.isEmpty)
    }

    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    controller.beginTransitionCollection()
    controller.finishTransitionCollection()
    controller.processResolvedTree(
      animationTemporalRoot(identity: rootID),
      transaction: transaction,
      timestamp: start.advanced(by: .milliseconds(40))
    )
    withKnownIssue("A stale transition registration animates a later removal") {
      #expect(controller.debugStateSnapshot().removingIdentities.isEmpty)
    }
  }
}

// MARK: - Attempt 020: live transition replacement

extension FrameworkStressAnimationTemporalTests {
  @Test("stress animation temporal 020 removal uses latest transition effect")
  func animationTemporal020RemovalUsesLatestTransitionEffect() throws {
    // Hypothesis: previous-transition rollover can preserve the first effect
    // after the stable node changes its transition declaration.
    let controller = AnimationController()
    let animation = Animation.linear(duration: .seconds(1))
    controller.register(animation)
    let rootID = testIdentity("AnimationTemporal020", "Root")
    let leafID = testIdentity("AnimationTemporal020", "Leaf")
    let nodeID = ViewNodeID(rawValue: 20)
    let start = MonotonicInstant(offset: .seconds(90))
    let leaf = animationTemporalNode(identity: leafID, viewNodeID: nodeID)
    let shown = animationTemporalRoot(identity: rootID, children: [leaf])

    controller.beginTransitionCollection()
    controller.registerTransition(
      for: leafID, viewNodeID: nodeID, transition: AnyTransition.opacity)
    controller.finishTransitionCollection()
    controller.processResolvedTree(shown, transaction: .init(), timestamp: start)

    controller.beginTransitionCollection()
    controller.registerTransition(
      for: leafID,
      viewNodeID: nodeID,
      transition: AnyTransition.offset(x: 10)
    )
    controller.finishTransitionCollection()
    controller.processResolvedTree(
      shown,
      transaction: .init(),
      timestamp: start.advanced(by: .milliseconds(20))
    )

    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    controller.beginTransitionCollection()
    controller.finishTransitionCollection()
    var removed = animationTemporalRoot(identity: rootID)
    controller.processResolvedTree(
      removed,
      transaction: transaction,
      timestamp: start.advanced(by: .milliseconds(40))
    )
    _ = controller.applyInterpolations(
      to: &removed,
      at: start.advanced(by: .milliseconds(540))
    )
    #expect(animationTemporalContainsOffset(in: removed))
  }
}

// MARK: - Attempt 021: transition-free entity reorder

extension FrameworkStressAnimationTemporalTests {
  @Test("stress animation temporal 021 foreach reorder creates no transition work")
  func animationTemporal021ForEachReorderCreatesNoTransitionWork() throws {
    // Hypothesis: identity-set diffing can treat entity movement between row
    // positions as a removal plus insertion even though every entity survives.
    let renderer = DefaultRenderer()
    let controller = renderer.internalAnimationController
    let animation = Animation.linear(duration: .seconds(2))
    controller.register(animation)
    let identity = testIdentity("AnimationTemporal021", "Root")
    let proposal = ProposedSize(width: 40, height: 8)

    withAnimationSinks(controller) {
      _ = renderer.render(
        animationTemporal021View(rows: ["a", "b", "c"]),
        context: .init(identity: identity),
        proposal: proposal
      )
      var transaction = TransactionSnapshot()
      transaction.animationRequest = .animate(animation.animationBox)
      _ = renderer.render(
        animationTemporal021View(rows: ["c", "a", "b"]),
        context: .init(identity: identity, transaction: transaction),
        proposal: proposal
      )
    }

    #expect(controller.debugStateSnapshot().removingIdentities.isEmpty)
    #expect(controller.activeInsertionOffsetCount == 0)
  }
}

@MainActor
private func animationTemporal021View(rows: [String]) -> some View {
  VStack(alignment: .leading, spacing: 0) {
    ForEach(rows, id: \.self) { row in
      Text("021 row \(row)")
        .transition(.opacity.combined(with: .offset(x: 4)))
    }
  }
}

// MARK: - Attempt 022: entity reparent transition stability

extension FrameworkStressAnimationTemporalTests {
  @Test("stress animation temporal 022 stable entity reparent creates no false transition")
  func animationTemporal022StableEntityReparentCreatesNoFalseTransition() throws {
    // Hypothesis: transition diffing follows structural Identity rather than
    // ViewNodeID and animates a surviving entity when it changes parents.
    let controller = AnimationController()
    let animation = Animation.linear(duration: .seconds(2))
    controller.register(animation)
    let rootID = testIdentity("AnimationTemporal022", "Root")
    let leftID = testIdentity("AnimationTemporal022", "Left")
    let rightID = testIdentity("AnimationTemporal022", "Right")
    let oldLeafID = testIdentity("AnimationTemporal022", "Left", "Entity")
    let newLeafID = testIdentity("AnimationTemporal022", "Right", "Entity")
    let nodeID = ViewNodeID(rawValue: 22)
    let start = MonotonicInstant(offset: .seconds(100))

    controller.beginTransitionCollection()
    controller.registerTransition(
      for: oldLeafID,
      viewNodeID: nodeID,
      transition: AnyTransition.opacity
    )
    controller.finishTransitionCollection()
    controller.processResolvedTree(
      animationTemporalRoot(
        identity: rootID,
        children: [
          animationTemporalRoot(
            identity: leftID,
            children: [animationTemporalNode(identity: oldLeafID, viewNodeID: nodeID)]
          ),
          animationTemporalRoot(identity: rightID),
        ]
      ),
      transaction: .init(),
      timestamp: start
    )

    controller.beginTransitionCollection()
    controller.registerTransition(
      for: newLeafID,
      viewNodeID: nodeID,
      transition: AnyTransition.opacity
    )
    controller.finishTransitionCollection()
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    controller.processResolvedTree(
      animationTemporalRoot(
        identity: rootID,
        children: [
          animationTemporalRoot(identity: leftID),
          animationTemporalRoot(
            identity: rightID,
            children: [animationTemporalNode(identity: newLeafID, viewNodeID: nodeID)]
          ),
        ]
      ),
      transaction: transaction,
      timestamp: start.advanced(by: .milliseconds(40))
    )

    withKnownIssue("A reparented ViewNodeID is treated as transition removal and insertion") {
      #expect(controller.debugStateSnapshot().removingIdentities.isEmpty)
      #expect(controller.activeAnimationCount == 0)
    }
  }
}

// MARK: - Attempt 023: duplicate identity occurrence removal

extension FrameworkStressAnimationTemporalTests {
  @Test("stress animation temporal 023 duplicate identity removal tracks departed occurrence")
  func animationTemporal023DuplicateIdentityRemovalTracksDepartedOccurrence() throws {
    // Hypothesis: set-based identity diffing collapses duplicate occurrences
    // and cannot discover that exactly one registered node departed.
    let controller = AnimationController()
    let animation = Animation.linear(duration: .seconds(1))
    controller.register(animation)
    let rootID = testIdentity("AnimationTemporal023", "Root")
    let duplicateID = testIdentity("AnimationTemporal023", "Duplicate")
    let firstNodeID = ViewNodeID(rawValue: 231)
    let secondNodeID = ViewNodeID(rawValue: 232)
    let start = MonotonicInstant(offset: .seconds(110))

    controller.beginTransitionCollection()
    controller.registerTransition(
      for: duplicateID,
      viewNodeID: firstNodeID,
      transition: AnyTransition.opacity
    )
    controller.registerTransition(
      for: duplicateID,
      viewNodeID: secondNodeID,
      transition: AnyTransition.opacity
    )
    controller.finishTransitionCollection()
    controller.processResolvedTree(
      animationTemporalRoot(
        identity: rootID,
        children: [
          animationTemporalNode(identity: duplicateID, viewNodeID: firstNodeID),
          animationTemporalNode(identity: duplicateID, viewNodeID: secondNodeID),
        ]
      ),
      transaction: .init(),
      timestamp: start
    )

    controller.beginTransitionCollection()
    controller.registerTransition(
      for: duplicateID,
      viewNodeID: firstNodeID,
      transition: AnyTransition.opacity
    )
    controller.finishTransitionCollection()
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    controller.processResolvedTree(
      animationTemporalRoot(
        identity: rootID,
        children: [animationTemporalNode(identity: duplicateID, viewNodeID: firstNodeID)]
      ),
      transaction: transaction,
      timestamp: start.advanced(by: .milliseconds(40))
    )

    withKnownIssue("Duplicate Identity diffing misses a departed ViewNodeID occurrence") {
      #expect(controller.debugStateSnapshot().removingNodeIDs.count == 1)
    }
  }
}

