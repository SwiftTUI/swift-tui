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

