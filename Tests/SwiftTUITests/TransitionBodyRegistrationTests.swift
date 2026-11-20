@_spi(Testing) import SwiftTUITestSupport
import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIGraph
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// What a host registers for a transition with a body, and the scratch scope
/// that evaluates a phase which is not on screen (STUI-1544).
@MainActor
@Suite("Transition body registration", .serialized)
struct TransitionBodyRegistrationTests {
  private static let transactionAnimation = Animation.linear(duration: .milliseconds(800))

  // MARK: - The registration payload

  @Test("a host registers its resolve context without a graph, and its content boundary")
  func hostRegistersADetachedContextAndItsBoundary() throws {
    let mounted = try RegisteredBody.mount(Text("PRESENT").transition(Dim()))
    let registration = try #require(mounted.registration)
    let boundary = try #require(mounted.boundaries.first)
    #expect(mounted.boundaries.count == 1)

    // The same place and the same environment as the live body.
    let context = registration.context
    #expect(registration.identity == boundary.identity)
    #expect(context.identity == boundary.identity)
    #expect(context.structuralPath == boundary.structuralPath)
    #expect(context.environment == boundary.environmentSnapshot)
    // A plain transaction: no animation request and no batch.
    #expect(context.transaction.animationRequest == .inherit)
    #expect(context.transaction.animationBatchID == nil)
    #expect(context.invalidatedIdentities.isEmpty)

    // Nothing that reaches live state.
    #expect(context.viewGraph == nil)
    #expect(context.resolveWorkTracker == nil)
    #expect(context.localActionRegistry == nil)
    #expect(context.localKeyHandlerRegistry == nil)
    #expect(context.localLifecycleRegistry == nil)
    #expect(context.localTaskRegistry == nil)
    #expect(context.localGestureRegistry == nil)
    #expect(context.localGestureStateRegistry == nil)
    #expect(context.localPointerHandlerRegistry == nil)
    #expect(context.localTerminationRegistry == nil)
    #expect(context.localDefaultFocusRegistry == nil)
    #expect(context.localFocusBindingRegistry == nil)
    #expect(context.localFocusedValuesRegistry == nil)
    #expect(context.localScrollPositionRegistry == nil)
    #expect(context.liveScrollPositionRegistry == nil)
    #expect(context.liveFocusBindingRegistry == nil)
    #expect(context.liveGestureRegistry == nil)
    #expect(context.localPreferenceObservationRegistry == nil)
    #expect(context.commandRegistry == nil)
    #expect(context.dropDestinationRegistry == nil)
    #expect(context.invalidationProxy == nil)
    #expect(context.observationBridge == nil)
    #expect(context.frameInputs == nil)
    #expect(context.requestDeadline == nil)
    #expect(context.presentationTriggerObserver == nil)

    #expect(registration.boundaryIdentities == [boundary.identity])
    #expect(registration.transitionTypeDescription == "Dim")
  }

  @Test("a registration names the boundaries whose child is the content")
  func registrationNamesTheContentBoundaries() throws {
    // Content placed twice: two boundaries, in tree order.
    let twice = try RegisteredBody.mount(Text("PRESENT").transition(Stacked()))
    #expect(twice.contentBoundaries.count == 2)
    #expect(twice.registration?.boundaryIdentities == twice.contentBoundaries.map(\.identity))

    // Two custom bodies nest two boundaries. The inner one holds the content.
    for mounted in [
      try RegisteredBody.mount(Text("PRESENT").transition(Dim().combined(with: Bracketed()))),
      // The same type on both sides of an asymmetric pair.
      try RegisteredBody.mount(
        Text("PRESENT").transition(AsymmetricTransition(insertion: Dim(), removal: Dim()))),
      // A built-in applied inside a body places its own boundary further out.
      try RegisteredBody.mount(Text("PRESENT").transition(DimThroughBuiltIn())),
    ] {
      #expect(mounted.boundaries.count == 2)
      let content = try #require(mounted.contentBoundaries.first)
      #expect(mounted.contentBoundaries.count == 1)
      #expect(mounted.registration?.boundaryIdentities == [content.identity])
    }

    // A view the body adds carries a custom transition of its own. Its
    // boundary is not a content boundary of the body that adds it.
    let nested = try RegisteredBody.mount(Text("PRESENT").transition(AddsATransitionedView()))
    #expect(nested.boundaries.count == 2)
    let own = try #require(
      nested.boundaries.first { $0.children.first?.drawPayload == .text("PRESENT") })
    let registrations = nested.controller.debugStateSnapshot().transitionIdentities.compactMap {
      nested.controller.transitionBodyRegistration(forIdentity: $0)
    }
    #expect(registrations.count == 2)
    #expect(
      registrations.first { $0.transitionTypeDescription == "AddsATransitionedView" }?
        .boundaryIdentities == [own.identity])

    // A mixed transition registers its body. A transition without a body
    // registers none.
    let mixed = try RegisteredBody.mount(
      Text("PRESENT").transition(AnyTransition(Dim()).combined(with: .opacity)))
    #expect(mixed.registration?.boundaryIdentities == mixed.contentBoundaries.map(\.identity))
    let effects = try RegisteredBody.mount(Text("PRESENT").transition(.opacity))
    #expect(effects.controller.debugStateSnapshot().transitionIdentities.count == 1)
    #expect(effects.registration == nil)
  }

  // MARK: - The scratch scope

  @Test("a scratch phase has the identities of the live body", arguments: 0..<9)
  func scratchPhaseSharesTheLiveIdentities(index: Int) throws {
    let mounted: RegisteredBody
    switch index {
    case 0: mounted = try RegisteredBody.mount(Text("PRESENT").transition(Dim()))
    case 1: mounted = try RegisteredBody.mount(Text("PRESENT").transition(Bracketed()))
    case 2: mounted = try RegisteredBody.mount(Text("PRESENT").transition(Decorated()))
    case 3: mounted = try RegisteredBody.mount(Text("PRESENT").transition(Stacked()))
    case 4: mounted = try RegisteredBody.mount(Text("PRESENT").transition(Branching()))
    case 5: mounted = try RegisteredBody.mount(Text("PRESENT").transition(Erased()))
    case 6:
      mounted = try RegisteredBody.mount(
        Text("PRESENT").transition(Dim().combined(with: Bracketed())))
    case 7:
      mounted = try RegisteredBody.mount(
        Text("PRESENT").transition(AsymmetricTransition(insertion: Decorated(), removal: Dim())))
    default: mounted = try RegisteredBody.mount(Text("PRESENT").transition(DimThroughBuiltIn()))
    }
    let registration = try #require(mounted.registration)
    let tree = registration.resolve(phase: .identity)

    // Every node of the scratch body except the stand-ins is a node of the
    // live body at the same identity and of the same kind, and the reverse.
    var scratch: [Identity: NodeKind] = [:]
    var standIns: [ResolvedNode] = []
    func collect(_ node: ResolvedNode) {
      if node.kind == .view(.transitionContentStandIn) {
        standIns.append(node)
        return
      }
      scratch[node.identity] = node.kind
      node.children.forEach(collect)
    }
    tree.roots.forEach(collect)
    #expect(scratch == mounted.wrapperKinds, "case \(index)")

    // Each stand-in is a leaf at the identity of the live content.
    #expect(standIns.map(\.identity) == tree.contentIdentities)
    #expect(
      tree.contentIdentities
        == registration.boundaryIdentities.map { $0.child(.named("content")) })
    #expect(standIns.allSatisfy { $0.children.isEmpty && $0.intrinsicSize == .zero })

    // The stand-in takes the size the caller gives it.
    let sized = registration.resolve(phase: .didDisappear) { _ in CellSize(width: 7, height: 1) }
    var sizes: [CellSize?] = []
    func collectSizes(_ node: ResolvedNode) {
      if node.kind == .view(.transitionContentStandIn) { sizes.append(node.intrinsicSize) }
      node.children.forEach(collectSizes)
    }
    sized.roots.forEach(collectSizes)
    #expect(sizes == tree.contentIdentities.map { _ in CellSize(width: 7, height: 1) })
  }

  @Test("a scratch phase carries the values of its phase")
  func scratchPhaseCarriesItsValues() throws {
    let mounted = try RegisteredBody.mount(Text("PRESENT").transition(Dim()))
    let registration = try #require(mounted.registration)
    for (phase, opacity) in [
      (TransitionPhase.willAppear, 0.25), (.identity, 1.0), (.didDisappear, 0.25),
    ] {
      let root = try #require(registration.resolve(phase: phase).roots.first)
      #expect(root.drawMetadata.baseStyle.explicitOpacity == opacity)
      #expect(root.viewNodeID == nil)
    }
  }

  @Test("a scratch resolve reaches no live state")
  func scratchResolveIsIsolated() throws {
    let log = RegistrationProbeLog()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("transition-registration", "isolation"),
      size: .init(width: 40, height: 6)
    ) {
      VStack(alignment: .leading, spacing: 0) {
        Text("host")
        Text("PRESENT").transition(Busy(log: log))
      }
    }
    defer { harness.shutdown() }
    harness.runLoop.runtimeIssueSink = RuntimeIssueSink { log.issues.append($0) }
    // A fixed clock: no frame deadline comes due on its own, so the only
    // frame after the mount is the one this test asks for.
    let instant = MonotonicInstant.now()
    harness.runLoop.frameClock = { instant }
    let renderer = harness.runLoop.renderer
    let controller = renderer.internalAnimationController
    let registered = try #require(
      controller.debugStateSnapshot().transitionIdentities.compactMap {
        controller.transitionBodyRegistration(forIdentity: $0)
      }.first { $0.transitionTypeDescription == "Busy" })

    // The live body mounted its views: one appearance and one task.
    #expect(log.appears == 1)
    #expect(harness.activeTaskCount == 1)

    /// Everything a resolve can register with, outside the resolved tree.
    struct LiveState: Equatable {
      var transitionNodeIDs: Set<ViewNodeID>
      var transitionIdentities: Set<Identity>
      var activeAnimationKeys: Set<AnimationKey>
      var registeredAnimationCount: Int
      var completionBatches: Set<AnimationBatchID>
      var liveNodes: Set<ViewNodeID>
      var lifecycle: Int
      var tasks: Int
      var taskDescriptors: Int
      var actions: Int
      var pointerHandlers: Int
      var gestures: Int
      var focusRegions: Int
      var focusBindings: Int
      var preferenceObservers: Int
      var pendingIssues: [RuntimeIssue]
      var appears: Int
      var disappears: Int
    }
    func liveState() -> LiveState {
      let snapshot = controller.debugStateSnapshot()
      return LiveState(
        transitionNodeIDs: snapshot.transitionNodeIDs,
        transitionIdentities: snapshot.transitionIdentities,
        activeAnimationKeys: snapshot.activeAnimationKeys,
        registeredAnimationCount: snapshot.registeredAnimationCount,
        completionBatches: snapshot.completionClosureBatchIDs,
        liveNodes: renderer.liveNodeIDSnapshot(),
        lifecycle: harness.lifecycleRegistrationCount,
        tasks: harness.activeTaskCount,
        taskDescriptors: harness.activeTaskDescriptorCount,
        actions: harness.actionRegistrationCount,
        pointerHandlers: harness.pointerHandlerCount,
        gestures: harness.gestureRecognizerCount,
        focusRegions: harness.focusRegionCount,
        focusBindings: harness.focusBindingRegistrationCount,
        preferenceObservers: harness.preferenceObservationRegistrationCount,
        pendingIssues: ImperativeRuntimeIssueQueue.pending,
        appears: log.appears,
        disappears: log.disappears)
    }
    let before = liveState()
    let controllerBefore = controller.debugStateSnapshot()
    let evaluationsBefore = log.bodyEvaluations

    // With the sinks bound, as they are while a frame is produced.
    let trees = withAnimationSinks(controller) {
      [TransitionPhase.willAppear, .identity, .didDisappear].map {
        registered.resolve(phase: $0)
      }
    }
    // The body ran in each phase and produced its views, the ones with
    // lifecycle handlers, a task, an action and a transition among them.
    #expect(log.bodyEvaluations == evaluationsBefore + 3)
    for tree in trees {
      var texts: [String] = []
      func collect(_ node: ResolvedNode) {
        if case .text(let text) = node.drawPayload { texts.append(text) }
        node.children.forEach(collect)
      }
      tree.roots.forEach(collect)
      #expect(texts.contains("added"))
      #expect(texts.contains { $0.hasPrefix("tap") })
    }
    // Nothing moved: not one field of the controller (its three sets of
    // registration maps among them), no registry, no graph node, no queued
    // diagnostic.
    #expect(controller.debugStateSnapshot() == controllerBefore)
    #expect(liveState() == before)

    // The next frame finds nothing the scratch phases left behind, and the
    // lifecycle plan it commits starts and ends nothing.
    _ = try harness.renderAfterExternalMutation()
    #expect(liveState() == before)
    #expect(log.issues.isEmpty, "\(log.issues)")
  }

  @Test("an insertion that evaluates the willAppear phase mounts the body once")
  func insertionMountsTheBodyOnce() throws {
    // The same insertion with and without an animation. Only the animated
    // one evaluates the willAppear phase; both leave the same registrations.
    var observed: [[Int]] = []
    for animated in [false, true] {
      let log = RegistrationProbeLog()
      let harness = try StressRuntimeHarness(
        rootIdentity: testIdentity("transition-registration", "mount-\(animated)"),
        size: .init(width: 40, height: 6)
      ) { RegistrationProbeRoot(log: log) }
      defer { harness.shutdown() }
      harness.runLoop.runtimeIssueSink = RuntimeIssueSink { log.issues.append($0) }
      let instant = MonotonicInstant.now()
      harness.runLoop.frameClock = { instant }
      let controller = harness.runLoop.renderer.internalAnimationController
      let shown = try #require(log.shown)
      try withAnimationSinks(controller) {
        if animated {
          withAnimation(Self.transactionAnimation) { shown.wrappedValue = true }
        } else {
          shown.wrappedValue = true
        }
        _ = try harness.render()
      }
      // The body's opacity animates only in the animated run. (Focus arrives
      // on the added button in both runs, and its own style change animates
      // under the transaction as any change would.)
      let opacityKeys = controller.debugStateSnapshot().activeAnimationKeys.filter {
        $0.scope == .property(.opacity)
      }
      #expect(opacityKeys.count == (animated ? 1 : 0))
      #expect(log.issues.isEmpty, "\(log.issues)")
      observed.append([
        log.appears, harness.activeTaskCount, harness.lifecycleRegistrationCount,
        harness.actionRegistrationCount,
        controller.debugStateSnapshot().transitionIdentities.count,
        harness.runLoop.renderer.liveNodeIDSnapshot().count,
      ])
    }
    #expect(observed[0] == observed[1])
    // One appearance, one task, and two transitions: the body's own and the
    // one on the view it adds.
    #expect(observed[1][0] == 1)
    #expect(observed[1][1] == 1)
    #expect(observed[1][4] == 2)
  }

  // MARK: - The controller

  @Test("the registration survives the frame draft and reaches a removal entry")
  func registrationTravelsWithTheTransition() throws {
    let log = RegistrationProbeLog()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("transition-registration", "travel"),
      size: .init(width: 40, height: 6)
    ) { RegistrationProbeRoot(log: log, transition: AnyTransition(Dim()).combined(with: .opacity)) }
    defer { harness.shutdown() }
    let instant = MonotonicInstant.now()
    harness.runLoop.frameClock = { instant }
    let controller = harness.runLoop.renderer.internalAnimationController
    let shown = try #require(log.shown)
    try withAnimationSinks(controller) {
      shown.wrappedValue = true
      _ = try harness.render()
      // Each frame works on a draft of the controller and publishes it. The
      // live controller holds the registration afterwards.
      let identity = try #require(controller.debugStateSnapshot().transitionIdentities.first)
      let registration = try #require(controller.transitionBodyRegistration(forIdentity: identity))
      #expect(registration.identity == identity)
      #expect(registration.boundaryIdentities.count == 1)

      // The effect channel of this mixed transition plans a removal overlay.
      // Its entry carries the same registration.
      withAnimation(Self.transactionAnimation) { shown.wrappedValue = false }
      _ = try harness.render()
      #expect(controller.debugStateSnapshot().removingNodeIDs.count == 1)
      let carried = try #require(controller.removalBodyRegistration(forIdentity: identity))
      #expect(carried.identity == registration.identity)
      #expect(carried.boundaryIdentities == registration.boundaryIdentities)
      #expect(carried.context == registration.context)
      let root = try #require(carried.resolve(phase: .didDisappear).roots.first)
      #expect(root.drawMetadata.baseStyle.explicitOpacity == 0.25)
    }
  }

  @Test("a registered body animates through the controller alone")
  func controllerAnimatesARegisteredBody() throws {
    let controller = AnimationController()
    controller.register(Self.transactionAnimation)
    let host = testIdentity("transition-registration", "controller")
    let item = host.child(.named("item"))
    let start = MonotonicInstant(offset: .seconds(50))
    func tree(present: Bool) -> ResolvedNode {
      var boundary = ResolvedNode(
        viewNodeID: ViewNodeID(rawValue: 2),
        identity: item,
        kind: .view(.transitionContent),
        typeDiscriminator: TransitionContent<Dim>.boundaryType,
        children: [
          ResolvedNode(
            viewNodeID: ViewNodeID(rawValue: 3),
            identity: item.child(.named("content")),
            kind: .view(.text),
            drawPayload: .text("PRESENT"))
        ])
      var metadata = boundary.drawMetadata
      metadata.baseStyle.explicitOpacity = 1
      boundary.drawMetadata = metadata
      return ResolvedNode(
        viewNodeID: ViewNodeID(rawValue: 1),
        identity: host,
        kind: .view(.vStack),
        children: present ? [boundary] : [])
    }
    var animated = TransactionSnapshot()
    animated.animationRequest = .animate(Self.transactionAnimation.animationBox)

    controller.processResolvedTree(tree(present: false), transaction: .init(), timestamp: start)
    controller.beginTransitionCollection()
    let registered = AnyTransition(Dim()).registeringBody(
      in: ResolveContext(identity: item), emitting: tree(present: true).children)
    #expect(registered.bodyRegistration?.boundaryIdentities == [item])
    controller.registerTransition(
      for: item, viewNodeID: ViewNodeID(rawValue: 2), transition: registered)
    controller.finishTransitionCollection()
    controller.processResolvedTree(tree(present: true), transaction: animated, timestamp: start)
    #expect(
      controller.debugStateSnapshot().activeAnimationKeys == [
        AnimationKey(identity: item, slot: .opacity)
      ])

    // The opacity runs from the willAppear value, 0.25, to the live value.
    for (offset, expected) in [(0, 0.25), (400, 0.625), (800, 1.0)] {
      var presented = tree(present: true)
      _ = controller.applyInterpolations(
        to: &presented, at: start.advanced(by: .milliseconds(offset)))
      let opacity = try #require(presented.children.first?.drawMetadata.baseStyle.explicitOpacity)
      #expect(abs(opacity - expected) < 1e-9, "\(offset) ms: \(opacity)")
    }
    #expect(controller.activeAnimationCount == 0)
  }

  @Test("a body transition registered without a host registration snaps")
  func bareBodyTransitionSnaps() throws {
    let controller = AnimationController()
    controller.register(Self.transactionAnimation)
    let host = testIdentity("transition-registration", "bare")
    let item = host.child(.named("item"))
    let start = MonotonicInstant(offset: .seconds(50))
    func tree(present: Bool) -> ResolvedNode {
      ResolvedNode(
        viewNodeID: ViewNodeID(rawValue: 1),
        identity: host,
        kind: .view(.vStack),
        children: present
          ? [
            ResolvedNode(
              viewNodeID: ViewNodeID(rawValue: 2), identity: item, kind: .view(.text),
              drawPayload: .text("PRESENT"))
          ] : [])
    }
    var animated = TransactionSnapshot()
    animated.animationRequest = .animate(Self.transactionAnimation.animationBox)
    controller.processResolvedTree(tree(present: false), transaction: .init(), timestamp: start)
    controller.beginTransitionCollection()
    // The call shape a direct test uses: a transition no host registered.
    let bare = AnyTransition(Dim())
    #expect(bare.bodyBox != nil && bare.bodyRegistration == nil)
    controller.registerTransition(for: item, viewNodeID: ViewNodeID(rawValue: 2), transition: bare)
    controller.finishTransitionCollection()
    controller.processResolvedTree(tree(present: true), transaction: animated, timestamp: start)
    #expect(controller.activeAnimationCount == 0)
    #expect(controller.transitionBodyRegistration(forIdentity: item) == nil)
  }
}

// MARK: - Transitions

private struct Dim: Transition {
  func body(content: Content, phase: TransitionPhase) -> some View {
    content.opacity(phase.isIdentity ? 1 : 0.25)
  }
}

private struct Bracketed: Transition {
  func body(content: Content, phase: TransitionPhase) -> some View {
    HStack(spacing: 0) {
      Text("[")
      content
      Text("]")
    }
  }
}

/// Layout and drawing wrappers, an overlay and a background.
private struct Decorated: Transition {
  func body(content: Content, phase: TransitionPhase) -> some View {
    content
      .padding(phase.isIdentity ? 0 : 1)
      .border(Color.white)
      .offset(x: phase.isIdentity ? 0 : 2, y: 0)
      .overlay(alignment: .topTrailing) { Text("*") }
      .background { Text("~") }
      .frame(width: 14, height: 3)
  }
}

private struct Stacked: Transition {
  func body(content: Content, phase: TransitionPhase) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      content
      Group {
        Text("between")
        ForEach(0..<2, id: \.self) { index in Text("row \(index)") }
      }
      content.id("second")
    }
  }
}

/// A conditional whose branch does not depend on the phase.
private struct Branching: Transition {
  var wide = true

  func body(content: Content, phase: TransitionPhase) -> some View {
    ZStack {
      if wide {
        content.padding(.horizontal, 2)
      } else {
        content
      }
    }
  }
}

private struct Erased: Transition {
  func body(content: Content, phase: TransitionPhase) -> some View {
    AnyView(content.opacity(phase.isIdentity ? 1 : 0.5))
  }
}

private struct DimThroughBuiltIn: Transition {
  func body(content: Content, phase: TransitionPhase) -> some View {
    OpacityTransition().apply(content: content, phase: phase)
  }
}

private struct AddsATransitionedView: Transition {
  func body(content: Content, phase: TransitionPhase) -> some View {
    HStack(spacing: 1) {
      content
      Text("added").transition(Dim())
    }
  }
}

/// A body with everything a resolve can register: lifecycle handlers, a
/// task, an action, a transition and a value-gated animation.
private struct Busy: Transition {
  let log: RegistrationProbeLog

  func body(content: Content, phase: TransitionPhase) -> some View {
    let _ = log.noteBodyEvaluation()
    HStack(spacing: 1) {
      content.opacity(phase.isIdentity ? 1 : 0.25)
      Text("added")
        .transition(.opacity)
        .animation(.linear(duration: .milliseconds(100)), value: phase)
        .onAppear { log.appears += 1 }
        .onDisappear { log.disappears += 1 }
        .task { await suspendUntilCancelled() }
      BusyButton()
    }
  }
}

private struct BusyButton: View {
  @State private var taps = 0

  var body: some View {
    Button("tap \(taps)") { taps += 1 }
  }
}

// MARK: - Fixtures

@MainActor
private final class RegistrationProbeLog {
  var shown: Binding<Bool>?
  var issues: [RuntimeIssue] = []
  var appears = 0
  var disappears = 0
  var bodyEvaluations = 0

  func noteBodyEvaluation() {
    bodyEvaluations += 1
  }
}

private struct RegistrationProbeRoot: View {
  @State private var shown = false
  let log: RegistrationProbeLog
  var transition: AnyTransition?

  var body: some View {
    let _ = capture()
    VStack(alignment: .leading, spacing: 0) {
      Text("host")
      if shown {
        if let transition {
          Text("PRESENT").transition(transition)
        } else {
          Text("PRESENT").transition(Busy(log: log))
        }
      }
    }
  }

  private func capture() {
    log.shown = $shown
  }
}

/// One view with a transition, rendered at rest.
@MainActor
private struct RegisteredBody {
  var controller: AnimationController
  var resolved: ResolvedNode

  static func mount<V: View>(_ view: V) throws -> RegisteredBody {
    let renderer = DefaultRenderer()
    let controller = renderer.internalAnimationController
    let artifacts = withAnimationSinks(controller) {
      renderer.renderArtifacts(
        VStack(alignment: .leading, spacing: 0) {
          Text("STAYS")
          view
        },
        context: .init(identity: testIdentity("transition-registration", "mounted")),
        proposal: .init(width: .finite(30), height: .finite(8)))
    }
    return RegisteredBody(controller: controller, resolved: artifacts.resolvedTree)
  }

  /// The registration of the one body transition, or of the first when a
  /// body adds a view with a transition of its own.
  var registration: TransitionBodyRegistration? {
    controller.debugStateSnapshot().transitionIdentities
      .compactMap { controller.transitionBodyRegistration(forIdentity: $0) }
      .min { $0.identity.path.count < $1.identity.path.count }
  }

  /// Every boundary node of the live tree, in tree order.
  var boundaries: [ResolvedNode] {
    func collect(_ node: ResolvedNode) -> [ResolvedNode] {
      (node.kind == .view(.transitionContent) ? [node] : []) + node.children.flatMap(collect)
    }
    return collect(resolved)
  }

  /// The boundaries whose child is the content, in tree order.
  var contentBoundaries: [ResolvedNode] {
    boundaries.filter { $0.children.first?.drawPayload == .text("PRESENT") }
  }

  /// Identity and kind of every live node of the body: from the registered
  /// root down to the content boundaries, without the content.
  var wrapperKinds: [Identity: NodeKind] {
    guard let registration,
      let root = AnimationTreeQueries.findResolvedSubtree(
        in: resolved, identity: registration.identity)
    else { return [:] }
    let contentBoundaries = Set(registration.boundaryIdentities)
    var kinds: [Identity: NodeKind] = [:]
    func collect(_ node: ResolvedNode) {
      kinds[node.identity] = node.kind
      guard !contentBoundaries.contains(node.identity) else { return }
      node.children.forEach(collect)
    }
    collect(root)
    return kinds
  }
}
