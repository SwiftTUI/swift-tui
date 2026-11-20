import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIGraph
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// The engine side of the removal of a `Transition` body (STUI-1545): what a
/// removal entry carries, which animations it owns and where their samples
/// go, and that all of it is plain state of the controller.
///
/// These tests drive `AnimationController` with hand-built trees, the way
/// `AnimationControllerTests` does, and read the package-level state the
/// behavioural suite (`TransitionBodyRemovalTests`) does not look at.
@MainActor
@Suite("Transition body removal engine")
struct TransitionBodyRemovalEngineTests {
  private static let animation = Animation.linear(duration: .milliseconds(800))

  private static var animated: TransactionSnapshot {
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    return transaction
  }

  // MARK: - Ownership and sample routing

  @Test("a removal owns the animations of its body and takes their samples")
  func removalOwnsTheBodysAnimations() throws {
    let scene = RemovalScene(named: "ownership", transition: AnyTransition(EngineDim()))
    scene.mount()
    scene.remove(transaction: Self.animated)
    let controller = scene.controller
    let key = AnimationKey(identity: scene.item, slot: .opacity)

    // The entry carries the didDisappear body and owns the boundary, which
    // is in no live tree any more.
    let state = try #require(controller.removalBodyState(forIdentity: scene.item))
    #expect(state.ownedIdentities == [scene.item])
    #expect(state.rootIdentity == scene.item)
    #expect(state.workingRoot.drawMetadata.baseStyle.explicitOpacity == 0.25)
    #expect(state.contents.keys.map(\.path) == [scene.content.path])
    #expect(!state.hasEffectChannel)
    #expect(controller.debugStateSnapshot().activeAnimationKeys == [key])
    #expect(!controller.debugStateSnapshot().previousIdentities.contains(scene.item))

    // A tick samples the animation once and hands the value to the entry.
    // The live tree is not written.
    var live = scene.tree(present: false)
    let tick = controller.applyInterpolations(
      to: &live, at: scene.start.advanced(by: .milliseconds(400)))
    #expect(live == scene.tree(present: false))
    #expect(tick.hasPendingWork)
    let sample = try #require(
      controller.removalBodyState(forIdentity: scene.item)?.samples[scene.item]?[.opacity]?
        .unwrap(as: Double.self))
    #expect(abs(sample - 0.625) < 1e-9, "\(sample)")

    // The placed pass draws the body with that sample around the frozen
    // content, as a display-only overlay.
    var placed = scene.placed(present: false)
    controller.applyPlacedOverlays(to: &placed, at: scene.start.advanced(by: .milliseconds(400)))
    let overlay = try #require(Self.node(scene.item, in: placed))
    #expect(overlay.isTransient)
    #expect(abs((overlay.drawMetadata.baseStyle.explicitOpacity ?? -1) - 0.625) < 1e-9)
    let frozenContent = try #require(Self.node(scene.content, in: scene.placed(present: true)))
    let content = try #require(overlay.children.first)
    #expect(content.identity == scene.content)
    #expect(content.bounds == frozenContent.bounds)
    #expect(content.drawPayload == .text("PRESENT"))

    // The next frame's diff leaves the animation alone: its identity left
    // the tree, and it belongs to the removal.
    scene.process(present: false, transaction: .init(), milliseconds: 433)
    #expect(controller.debugStateSnapshot().activeAnimationKeys == [key])

    // When the animation ends the removal is over on that sample.
    var last = scene.tree(present: false)
    _ = controller.applyInterpolations(to: &last, at: scene.start.advanced(by: .milliseconds(800)))
    #expect(controller.debugStateSnapshot().activeAnimationKeys.isEmpty)
    let ended = controller.placedAnimationOverlaySnapshot(
      for: scene.placed(present: false), at: scene.start.advanced(by: .milliseconds(800)))
    #expect(ended.removalOverlays.isEmpty)
    #expect(controller.debugStateSnapshot().removingIdentities.isEmpty)
  }

  @Test("the body state of a removal rides the frame draft and the checkpoint")
  func removalStateSurvivesTheDraftAndTheCheckpoint() throws {
    let scene = RemovalScene(named: "checkpoint", transition: AnyTransition(EngineDim()))
    scene.mount()
    scene.remove(transaction: Self.animated)
    let controller = scene.controller
    let keys = controller.debugStateSnapshot().activeAnimationKeys
    try #require(keys.count == 1)

    // A frame draft is a copy of the controller. It has the entry and the
    // animation, and what it does to them stays in it until it commits.
    let draft = controller.makeFrameDraft()
    #expect(
      draft.controller.removalBodyState(forIdentity: scene.item)?.ownedIdentities == [scene.item])
    #expect(draft.controller.debugStateSnapshot().activeAnimationKeys == keys)
    scene.reinsert(on: draft.controller, transaction: Self.animated, milliseconds: 400)
    #expect(draft.controller.removalBodyState(forIdentity: scene.item) == nil)
    #expect(controller.removalBodyState(forIdentity: scene.item) != nil)
    draft.discard()
    #expect(controller.removalBodyState(forIdentity: scene.item) != nil)
    #expect(controller.debugStateSnapshot().activeAnimationKeys == keys)

    // An aborted frame-head transaction restores the entry it dropped.
    let checkpoint = controller.beginFrameHeadTransaction()
    scene.reinsert(on: controller, transaction: Self.animated, milliseconds: 400)
    #expect(controller.removalBodyState(forIdentity: scene.item) == nil)
    #expect(controller.debugStateSnapshot().removingIdentities.isEmpty)
    controller.abortFrameHeadTransaction(checkpoint)
    let restored = try #require(controller.removalBodyState(forIdentity: scene.item))
    #expect(restored.ownedIdentities == [scene.item])
    #expect(controller.debugStateSnapshot().removingIdentities == [scene.item])
    #expect(controller.debugStateSnapshot().activeAnimationKeys == keys)

    // A committed draft publishes the re-insertion: the entry is gone and the
    // animation it owned is the live view's, retargeted to the identity
    // value from the value the removal showed.
    let committed = controller.makeFrameDraft()
    scene.reinsert(on: committed.controller, transaction: Self.animated, milliseconds: 400)
    committed.commit()
    #expect(controller.removalBodyState(forIdentity: scene.item) == nil)
    #expect(controller.debugStateSnapshot().activeAnimationKeys == keys)
    var live = scene.tree(present: true)
    _ = controller.applyInterpolations(to: &live, at: scene.start.advanced(by: .milliseconds(400)))
    let opacity = try #require(live.children.first?.drawMetadata.baseStyle.explicitOpacity)
    // Half way from 1 to 0.25, where the removal was.
    #expect(abs(opacity - 0.625) < 1e-9, "\(opacity)")
  }

  // MARK: - What does not play

  @Test("without a cached placed tree a body snaps and a mixed transition plays its effects")
  func resolvedFallbackSnapsABody() throws {
    // No placed tree was captured, so a removal would take the resolved-level
    // fallback, which lays the overlay out with the live tree and cannot
    // host a body.
    let pure = RemovalScene(named: "fallback-pure", transition: AnyTransition(EngineDim()))
    pure.mount(capturingPlacedTree: false)
    pure.remove(transaction: Self.animated)
    #expect(pure.controller.debugStateSnapshot().removingIdentities.isEmpty)
    #expect(pure.controller.debugStateSnapshot().activeAnimationKeys.isEmpty)

    let mixed = RemovalScene(
      named: "fallback-mixed", transition: AnyTransition(EngineDim().combined(with: .opacity)))
    mixed.mount(capturingPlacedTree: false)
    mixed.remove(transaction: Self.animated)
    #expect(mixed.controller.debugStateSnapshot().removingIdentities == [mixed.item])
    #expect(mixed.controller.removalBodyRegistration(forIdentity: mixed.item) != nil)
    #expect(mixed.controller.removalBodyState(forIdentity: mixed.item) == nil)
    #expect(mixed.controller.debugStateSnapshot().activeAnimationKeys.isEmpty)
  }

  @Test("a removal without a curve carries no body")
  func removalWithoutACurveCarriesNoBody() throws {
    let mixed = RemovalScene(
      named: "no-curve", transition: AnyTransition(EngineDim().combined(with: .opacity)))
    mixed.mount()
    mixed.remove(transaction: .init())
    // The effect channel plans its entry as before, with no curve, and the
    // placed pass ends it on its first sample.
    #expect(mixed.controller.debugStateSnapshot().removingIdentities == [mixed.item])
    #expect(mixed.controller.removalBodyState(forIdentity: mixed.item) == nil)
    let snapshot = mixed.controller.placedAnimationOverlaySnapshot(
      for: mixed.placed(present: false), at: mixed.start)
    #expect(snapshot.removalOverlays.isEmpty)
    #expect(mixed.controller.debugStateSnapshot().removingIdentities.isEmpty)
  }

  // MARK: - One evaluation per curve per frame

  @Test("a body removal evaluates each of its curves once a frame")
  func eachCurveIsEvaluatedOnceAFrame() throws {
    // A stateful custom curve counts its evaluations in its own state. One
    // evaluation a frame keeps that count equal to the frame number.
    for (name, transition, streams) in [
      ("body", AnyTransition(EngineDim()), 1),
      // The effect channel of a mixed transition is a second curve, with a
      // state of its own.
      (
        "mixed",
        AnyTransition(EngineDim().combined(with: OffsetTransition(CellSize(width: 4, height: 0)))),
        2
      ),
    ] {
      let recorder = StateRecorder()
      let curve = Animation(
        RecordingCustomAnimation(id: "body-removal-\(name)", recorder: recorder))
      var transaction = TransactionSnapshot()
      transaction.animationRequest = .animate(curve.animationBox)
      let scene = RemovalScene(named: "once-\(name)", transition: transition)
      scene.controller.register(curve)
      scene.mount()
      scene.remove(transaction: transaction)
      #expect(recorder.callCount == 0, "\(name)")
      for frame in 0..<6 {
        let instant = scene.start.advanced(by: .milliseconds(33 * frame))
        if frame > 0 {
          scene.process(present: false, transaction: .init(), milliseconds: 33 * frame)
        }
        var live = scene.tree(present: false)
        _ = scene.controller.applyInterpolations(to: &live, at: instant)
        _ = scene.controller.placedAnimationOverlaySnapshot(
          for: scene.placed(present: false), at: instant)
        #expect(recorder.callCount == streams * (frame + 1), "\(name), frame \(frame)")
        #expect(recorder.lastObserved == frame, "\(name), frame \(frame)")
      }
    }
  }

  // MARK: - The registration payload and the issue codes

  @Test("a host records what its body alone stamped on each root")
  func hostRecordsWhatTheBodyStampedOnItsRoots() throws {
    let renderer = DefaultRenderer()
    let controller = renderer.internalAnimationController
    let artifacts = withAnimationSinks(controller) {
      renderer.renderArtifacts(
        VStack(alignment: .leading, spacing: 0) {
          Text("STAYS")
          Text("PRESENT").transition(EngineDim()).opacity(0.5).blendMode(.multiply)
        },
        context: .init(identity: testIdentity("transition-removal-engine", "stamps")),
        proposal: .init(width: .finite(30), height: .finite(4)))
    }
    let registration = try #require(
      controller.debugStateSnapshot().transitionIdentities
        .compactMap { controller.transitionBodyRegistration(forIdentity: $0) }.first)
    let root = try #require(
      AnimationTreeQueries.findResolvedSubtree(
        in: artifacts.resolvedTree, identity: registration.identity))
    // The node on screen has the body's opacity times the outer one, and the
    // outer blend mode. The registration has the body's own.
    #expect(root.drawMetadata.baseStyle.explicitOpacity == 0.5)
    #expect(root.drawEffects.ordered == [.blendMode(.multiply)])
    let stamps = try #require(registration.rootStamps[registration.identity])
    #expect(stamps.drawMetadata.baseStyle.explicitOpacity == 1)
    #expect(stamps.drawEffects.isEmpty)
    #expect(registration.rootStamps.count == 1)
  }

  @Test("the transition issue codes keep their wire values")
  func issueCodes() {
    #expect(RuntimeIssue.Code.Transition.phaseOnlyView.rawValue == "transition.phaseOnlyView")
    #expect(
      RuntimeIssue.Code.Transition.unsupportedBuiltInBody.rawValue
        == "transition.unsupportedBuiltInBody")
    #expect(
      RuntimeIssue.Code.Transition.removalContentNotFound.rawValue
        == "transition.removalContentNotFound")
    #expect(
      RuntimeIssue.Code.Transition.removalHandlersIgnored.rawValue
        == "transition.removalHandlersIgnored")
    #expect(
      RuntimeIssue.Code.Transition.removalEnvironmentIgnored.rawValue
        == "transition.removalEnvironmentIgnored")
  }

  private static func node(_ identity: Identity, in tree: PlacedNode) -> PlacedNode? {
    if tree.identity == identity { return tree }
    for child in tree.children {
      if let found = node(identity, in: child) { return found }
    }
    return nil
  }
}

/// An opacity of 0.25 outside the identity phase.
private struct EngineDim: Transition {
  func body(content: Content, phase: TransitionPhase) -> some View {
    content.opacity(phase.isIdentity ? 1 : 0.25)
  }
}

/// One controller and the two trees of a presence change: a stack that holds
/// the body's boundary around a text, or nothing.
@MainActor
private struct RemovalScene {
  let controller = AnimationController()
  let transition: AnyTransition
  let host: Identity
  let start = MonotonicInstant(offset: .seconds(50))

  init(named name: String, transition: AnyTransition) {
    host = testIdentity("transition-removal-engine", name)
    self.transition = transition
    controller.register(Animation.linear(duration: .milliseconds(800)))
  }

  var item: Identity { host.child(.named("item")) }
  var content: Identity { item.child(.named("content")) }

  func tree(present: Bool) -> ResolvedNode {
    var boundary = ResolvedNode(
      viewNodeID: ViewNodeID(rawValue: 2),
      identity: item,
      kind: .view(.transitionContent),
      typeDiscriminator: TransitionContent<EngineDim>.boundaryType,
      children: [
        ResolvedNode(
          viewNodeID: ViewNodeID(rawValue: 3),
          identity: content,
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

  func placed(present: Bool) -> PlacedNode {
    let engine = LayoutEngine()
    let resolved = tree(present: present)
    return engine.place(
      resolved,
      measured: engine.measure(resolved, proposal: ProposedSize(width: 20, height: 4)))
  }

  private func register(on controller: AnimationController) {
    controller.beginTransitionCollection()
    let registered = transition.registeringBody(
      in: ResolveContext(identity: item), emitting: tree(present: true).children)
    controller.registerTransition(
      for: item, viewNodeID: ViewNodeID(rawValue: 2), transition: registered)
    controller.finishTransitionCollection()
  }

  /// The frame that shows the view, one second before `start`.
  func mount(capturingPlacedTree: Bool = true) {
    register(on: controller)
    controller.processResolvedTree(
      tree(present: true), transaction: .init(), timestamp: start.advanced(by: .seconds(-1)))
    if capturingPlacedTree {
      controller.capturePlacedTree(placed(present: true))
    }
  }

  /// The frame that removes the view, at `start`.
  func remove(transaction: TransactionSnapshot) {
    process(present: false, transaction: transaction, milliseconds: 0)
  }

  /// A frame without the view's transition modifier in it.
  func process(present: Bool, transaction: TransactionSnapshot, milliseconds: Int) {
    controller.beginTransitionCollection()
    controller.finishTransitionCollection()
    controller.processResolvedTree(
      tree(present: present), transaction: transaction,
      timestamp: start.advanced(by: .milliseconds(milliseconds)))
  }

  /// The frame that shows the view again.
  func reinsert(
    on controller: AnimationController, transaction: TransactionSnapshot, milliseconds: Int
  ) {
    register(on: controller)
    controller.processResolvedTree(
      tree(present: true), transaction: transaction,
      timestamp: start.advanced(by: .milliseconds(milliseconds)))
  }
}
