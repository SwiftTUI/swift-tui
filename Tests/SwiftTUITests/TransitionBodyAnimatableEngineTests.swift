import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIGraph
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// The engine seams behind `Animatable` views and modifiers in a transition
/// body (STUI-1546): the sink a scratch phase asks, the names its sites get,
/// the frame head's decision for an insertion and the injection stage's use
/// of it, and a removal's ownership of the sites of its body.
///
/// These tests use the package API the change adds, so the file does not
/// compile against the earlier engine. The behaviour an app sees is in
/// `TransitionBodyAnimatableTests`.
@MainActor
@Suite("Animatable inside a transition body, engine", .serialized)
struct TransitionBodyAnimatableEngineTests {
  private static let linear = Animation.linear(duration: .milliseconds(800))
  private static let proposal = ProposedSize(width: .finite(30), height: .finite(4))

  // MARK: - The scratch sink

  @Test("the scratch sink records what a phase wrote and answers from supplied values")
  func sinkRecordsThePhaseAndAnswers() {
    let identity = testIdentity("body-site-engine", "sink")
    let first = AnimatableValueSite(identity: identity, ordinal: 0)
    let second = AnimatableValueSite(identity: identity, ordinal: 1)
    let third = AnimatableValueSite(identity: identity.child(.named("deeper")), ordinal: 0)
    let sink = TransitionBodyValueSink(answers: [
      AnimationKey(site: first): AnimationController.boxedAnimatableData(0.25),
      // A value of another type is not an answer for a `Double` site.
      AnimationKey(site: second): AnimationController.boxedAnimatableData(9),
    ])
    func pull(_ target: Double, at site: AnimatableValueSite) -> Double {
      sink.presentedAnimatableData(
        for: target, at: site, transaction: .init(), reducesMotion: false)
    }
    // A supplied value is presented in place of what the phase wrote.
    #expect(pull(1, at: first) == 0.25)
    // A site without one, or with one of another type, keeps its own data.
    #expect(pull(2, at: second) == 2)
    #expect(pull(3, at: third) == 3)
    // What the phase wrote is recorded for each site, in the order they
    // resolved, and a site that resolves again is listed once.
    #expect(pull(4, at: first) == 0.25)
    #expect(sink.sites == [first, second, third].map(AnimationKey.init(site:)))
    #expect(
      sink.phaseData[AnimationKey(site: first)] == AnimationController.boxedAnimatableData(4.0))
    #expect(
      sink.phaseData[AnimationKey(site: second)] == AnimationController.boxedAnimatableData(2.0))
    #expect(
      sink.phaseData[AnimationKey(site: third)] == AnimationController.boxedAnimatableData(3.0))
  }

  // MARK: - Site names

  @Test("every phase of a body names its sites as the live tree does, at every depth")
  func scratchPhasesNameTheLiveSites() throws {
    let log = AnimatableValueLog()
    let renderer = DefaultRenderer()
    let controller = renderer.internalAnimationController
    let root = testIdentity("body-site-engine", "names")
    try withAnimationSinks(controller) {
      _ = renderer.renderArtifacts(
        Text("PRESENT").transition(DeepSites(log: log)),
        context: .init(identity: root), proposal: Self.proposal,
        frameInstant: MonotonicInstant(offset: .seconds(10)))
      // The live body resolved four sites: a modifier at the identity the
      // body resolves at, a modifier further out at the same identity, and
      // two views below it, one of them inside a stack inside a stack.
      #expect(controller.valueSiteCount == 4)
      let registered = try #require(controller.debugStateSnapshot().transitionIdentities.first)
      let registration = try #require(
        controller.transitionBodyRegistration(forIdentity: registered))

      var names: [TransitionPhase: [AnimationKey]] = [:]
      for phase in [TransitionPhase.willAppear, .identity, .didDisappear] {
        let sink = TransitionBodyValueSink()
        _ = registration.resolve(phase: phase, valueSink: sink)
        names[phase] = sink.sites
        // Each site of the phase is a site the live tree has, under the same
        // identity and position.
        #expect(sink.sites.count == 4, "\(phase): \(sink.sites)")
        for key in sink.sites {
          guard case .value(let ordinal) = key.scope else {
            Issue.record("a site is named by a value key: \(key)")
            continue
          }
          #expect(
            controller.valueSites(forIdentity: key.identity).contains(
              AnimatableValueSite(identity: key.identity, ordinal: ordinal)),
            "\(phase): \(key.identity.path) #\(ordinal)")
        }
        // The phase's data is what the body wrote for the phase.
        let written = sink.sites.compactMap {
          sink.phaseData[$0]?.unwrap(as: AnimatableDataBox<Double>.self)?.animatableData
        }
        #expect(written == Array(repeating: phase.isIdentity ? 1 : 0, count: 4), "\(phase)")
      }
      #expect(names[.willAppear] == names[.identity])
      #expect(names[.didDisappear] == names[.identity])
      // Two of the four are at deeper identities than the body's own.
      let depths = Set((names[.identity] ?? []).map(\.identity))
      #expect(depths.count == 3, "\(depths.map(\.path))")
      // The scratch phases asked a sink of their own. The live controller's
      // records are what they were.
      #expect(controller.valueSiteCount == 4)
      #expect(controller.activeValueAnimationCount == 0)
    }
  }

  // MARK: - The frame head's decision

  @Test("the frame head starts the sites of an inserted body and the injection stage reads it")
  func headDecidesAndTheInjectionStageReads() throws {
    let controller = AnimationController()
    controller.register(Self.linear)
    let host = testIdentity("body-site-engine", "head")
    let item = host.child(.named("item"))
    let site = AnimatableValueSite(identity: item, ordinal: 0)
    let start = MonotonicInstant(offset: .seconds(50))
    let log = AnimatableValueLog()
    var animated = TransactionSnapshot()
    animated.animationRequest = .animate(Self.linear.animationBox)
    func tree(present: Bool, opacity: Double = 1) -> ResolvedNode {
      var boundary = ResolvedNode(
        viewNodeID: ViewNodeID(rawValue: 2),
        identity: item,
        kind: .view(.transitionContent),
        typeDiscriminator: TransitionContent<FadeSite>.boundaryType,
        children: [
          ResolvedNode(
            viewNodeID: ViewNodeID(rawValue: 3),
            identity: item.child(.named("content")),
            kind: .view(.text),
            drawPayload: .text("PRESENT"))
        ])
      var metadata = boundary.drawMetadata
      metadata.baseStyle.explicitOpacity = opacity
      boundary.drawMetadata = metadata
      return ResolvedNode(
        viewNodeID: ViewNodeID(rawValue: 1),
        identity: host,
        kind: .view(.vStack),
        children: present ? [boundary] : [])
    }
    func pull() -> Double {
      controller.presentedAnimatableData(
        for: 1.0, at: site, ownerNodeID: ViewNodeID(rawValue: 2), transaction: animated,
        reducesMotion: false)
    }
    func register() {
      let registered = AnyTransition(FadeSite(log: log)).registeringBody(
        in: ResolveContext(identity: item), emitting: tree(present: true).children)
      controller.registerTransition(
        for: item, viewNodeID: ViewNodeID(rawValue: 2), transition: registered)
    }

    // A frame without the view, then a frame that resolves nothing new: the
    // head has nothing to prepare.
    controller.processResolvedTree(tree(present: false), transaction: .init(), timestamp: start)
    #expect(controller.beginValueSiteFrame(at: start).isEmpty)
    controller.beginTransitionCollection()
    #expect(!controller.hasFreshTransitionBodySites)
    #expect(
      controller.prepareTransitionBodyInsertions(
        in: tree(present: false), transactionPlan: .init(base: animated)
      ).isEmpty)
    controller.finishTransitionCollection()

    // The insertion frame. The live body resolves first: its site pulls with
    // the data of the identity phase, and the host registers the transition.
    #expect(controller.beginValueSiteFrame(at: start).isEmpty)
    controller.beginTransitionCollection()
    #expect(pull() == 1)
    // A fresh site alone is not an insertion.
    #expect(!controller.hasFreshTransitionBodySites)
    register()
    #expect(controller.hasFreshTransitionBodySites)

    // The head qualifies the insertion on the tree as resolved so far, and
    // starts the site from the data of the `willAppear` phase.
    let owners = controller.prepareTransitionBodyInsertions(
      in: tree(present: true), transactionPlan: .init(base: animated))
    #expect(owners == [item])
    #expect(controller.pendingTransitionBodyInsertionDecisionCount == 1)
    #expect(controller.valueAnimationSites(forIdentity: item) == [site])
    #expect(
      controller.valueAnimationSample(at: site) == AnimationController.boxedAnimatableData(0.0))
    // The `willAppear` phase was evaluated for it, once.
    #expect(log.values == [0])
    // The owner runs again and now presents the origin. Its output is what
    // the `willAppear` body produces: opacity 0.25. The host registers
    // again, as it does whenever its node is evaluated.
    #expect(pull() == 0)
    register()
    controller.finishTransitionCollection()

    // The injection stage reads the decision. It evaluates no phase again,
    // and the slot the site drives does not animate: the tree already holds
    // the `willAppear` value there.
    controller.processResolvedTree(
      tree(present: true, opacity: 0.25), transaction: animated, timestamp: start)
    #expect(controller.pendingTransitionBodyInsertionDecisionCount == 0)
    #expect(log.values == [0])
    #expect(controller.activeAnimationCount == 0)
    #expect(controller.activeValueAnimationCount == 1)

    // A tick: the site is no longer fresh and the body was registered last
    // frame, so the head has nothing to prepare.
    let tick = start.advanced(by: .milliseconds(400))
    #expect(controller.beginValueSiteFrame(at: tick) == [item])
    controller.beginTransitionCollection()
    #expect(abs(pull() - 0.5) < 1e-9)
    register()
    #expect(!controller.hasFreshTransitionBodySites)
    controller.finishTransitionCollection()
    #expect(log.values == [0])
  }

  @Test("without the frame head's pass the injection stage decides as it always did")
  func injectionStageDecidesAlone() throws {
    let controller = AnimationController()
    controller.register(Self.linear)
    let host = testIdentity("body-site-engine", "alone")
    let item = host.child(.named("item"))
    let start = MonotonicInstant(offset: .seconds(50))
    let log = AnimatableValueLog()
    var animated = TransactionSnapshot()
    animated.animationRequest = .animate(Self.linear.animationBox)
    func tree(present: Bool) -> ResolvedNode {
      var boundary = ResolvedNode(
        viewNodeID: ViewNodeID(rawValue: 2),
        identity: item,
        kind: .view(.transitionContent),
        typeDiscriminator: TransitionContent<FadeSite>.boundaryType,
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
    controller.processResolvedTree(tree(present: false), transaction: .init(), timestamp: start)
    controller.beginTransitionCollection()
    let registered = AnyTransition(FadeSite(log: log)).registeringBody(
      in: ResolveContext(identity: item), emitting: tree(present: true).children)
    controller.registerTransition(
      for: item, viewNodeID: ViewNodeID(rawValue: 2), transition: registered)
    controller.finishTransitionCollection()
    // No site resolved through this controller, so no head pass ran. The
    // insertion is qualified and its `willAppear` phase evaluated here: the
    // slot animates from that phase's value, as before the change.
    #expect(controller.pendingTransitionBodyInsertionDecisionCount == 0)
    controller.processResolvedTree(tree(present: true), transaction: animated, timestamp: start)
    #expect(log.values == [0])
    #expect(
      controller.debugStateSnapshot().activeAnimationKeys == [
        AnimationKey(identity: item, slot: .opacity)
      ])
  }

  // MARK: - A removal's sites

  @Test("a removal owns the value animations of its body's sites")
  func removalOwnsTheSitesOfItsBody() throws {
    let scene = SiteFrames(named: "owns")
    try scene.run {
      scene.render(shown: true, at: 0)
      let live = try #require(scene.liveSite)
      #expect(scene.controller.valueSites(forIdentity: live.identity) == [live])

      scene.render(shown: false, animated: true, at: 33)
      let removal = try #require(scene.removalBody)
      let key = AnimationKey(site: live)
      // The site of the `didDisappear` body is the live site, and the
      // removal holds the data that phase gives it.
      #expect(removal.valueSites == [key: AnimationController.boxedAnimatableData(0.0)])
      // The animation at the key is the removal's own, and the removal lasts
      // as long as it does.
      #expect(removal.drivingKeys == [key])
      #expect(scene.controller.valueAnimationSites(forIdentity: live.identity) == [live])
      // No live site is left: the view's record went with it.
      #expect(scene.controller.valueSiteCount == 0)
      // The working tree shows the origin on the removal frame.
      #expect(removal.valueTreeIsAtRest == false)
      #expect(scene.log.values.last == 1)

      // The head samples the animation and names no owner for it: there is
      // no live view to run again.
      let draft = scene.controller.makeFrameDraft()
      let tick = scene.start.advanced(by: .milliseconds(33 + 400))
      #expect(draft.controller.beginValueSiteFrame(at: tick).isEmpty)
      #expect(
        draft.controller.valueAnimationSample(at: live)
          == AnimationController.boxedAnimatableData(0.5))
      draft.discard()

      // A frame of the removal evaluates the body with that frame's sample.
      scene.render(shown: false, at: 33 + 400)
      #expect(abs((scene.log.values.last ?? -1) - 0.5) < 1e-9)
      #expect(scene.removalBody?.valueTreeIsAtRest == false)

      // The animation ends on the frame past its duration, and the removal
      // with it. Nothing of the site is left.
      scene.render(shown: false, at: 33 + 825)
      scene.render(shown: false, at: 33 + 858)
      #expect(scene.removalBody == nil)
      #expect(scene.controller.debugStateSnapshot().activeAnimationKeys.isEmpty)
      #expect(scene.controller.valueSiteCount == 0)
    }
  }

  @Test("a removal's sites ride the frame draft and the checkpoint")
  func removalSitesRideTheDraft() throws {
    let scene = SiteFrames(named: "draft")
    try scene.run {
      scene.render(shown: true, at: 0)
      let live = try #require(scene.liveSite)
      let key = AnimationKey(site: live)
      scene.render(shown: false, animated: true, at: 33)
      scene.render(shown: false, at: 66)
      let before = scene.log.values.count

      // A draft starts from the live state, sites included.
      let draft = scene.controller.makeFrameDraft()
      let drafted = try #require(draft.controller.removalBodyState(forIdentity: live.identity))
      #expect(drafted.valueSites.keys.sorted { $0.identity.path < $1.identity.path } == [key])
      #expect(draft.controller.valueAnimationSites(forIdentity: live.identity) == [live])
      // What the draft does stays in the draft when it is dropped.
      _ = draft.controller.beginValueSiteFrame(
        at: scene.start.advanced(by: .milliseconds(33 + 825)))
      #expect(draft.controller.activeValueAnimationCount == 0)
      draft.discard()
      #expect(scene.controller.activeValueAnimationCount == 1)
      #expect(scene.removalBody?.valueSites.keys.contains(key) == true)

      // A prepared frame that is aborted leaves the removal where it was,
      // and its body unevaluated.
      scene.abort(shown: false, at: 99)
      #expect(scene.controller.activeValueAnimationCount == 1)
      #expect(scene.log.values.count == before)
      scene.render(shown: false, at: 99)
      #expect(abs((scene.log.values.last ?? -1) - (1 - 66.0 / 800)) < 1e-9)
    }
  }

  @Test("a view that comes back during its removal takes the removal's sites over")
  func reinsertionTakesTheSitesOver() throws {
    let scene = SiteFrames(named: "back")
    try scene.run {
      scene.render(shown: true, at: 0)
      let live = try #require(scene.liveSite)
      scene.render(shown: false, animated: true, at: 33)
      scene.render(shown: false, at: 33 + 200)
      #expect(abs((scene.log.values.last ?? -1) - 0.75) < 1e-9)

      // The view is inserted again 400 ms into the removal. The live site
      // resolves with its own data, the head hands it the removal's
      // animation, and it runs again from what the removal shows: 0.5.
      scene.render(shown: true, animated: true, at: 33 + 400)
      #expect(scene.removalBody == nil)
      #expect(scene.controller.debugStateSnapshot().removingNodeIDs.isEmpty)
      #expect(scene.controller.valueSites(forIdentity: live.identity) == [live])
      #expect(scene.controller.valueAnimationSites(forIdentity: live.identity) == [live])
      #expect(abs((scene.log.values.last ?? -1) - 0.5) < 1e-9)
      // The head's decision was read.
      #expect(scene.controller.pendingTransitionBodyInsertionDecisionCount == 0)

      // It then runs its own 800 ms to the identity data.
      scene.render(shown: true, at: 33 + 800)
      #expect(abs((scene.log.values.last ?? -1) - 0.75) < 1e-9)
      scene.render(shown: true, at: 33 + 1225)
      #expect(scene.log.values.last == 1)
      #expect(scene.controller.activeValueAnimationCount == 0)
    }
  }

  @Test("a view that comes back without an animation ends the removal's sites")
  func plainReinsertionEndsTheSites() throws {
    let scene = SiteFrames(named: "back-plain")
    try scene.run {
      scene.render(shown: true, at: 0)
      let live = try #require(scene.liveSite)
      scene.render(shown: false, animated: true, at: 33)
      scene.render(shown: false, at: 33 + 200)

      // No curve: the insertion snaps. The removal's animation of the site
      // ends, and the live site shows its own data.
      scene.render(shown: true, at: 33 + 400)
      #expect(scene.removalBody == nil)
      #expect(scene.log.values.last == 1)
      #expect(scene.controller.debugStateSnapshot().activeAnimationKeys.isEmpty)
      #expect(scene.controller.valueSites(forIdentity: live.identity) == [live])
      let settled = scene.log.values.count
      scene.render(shown: true, at: 33 + 433)
      #expect(scene.log.values[settled...].allSatisfy { $0 == 1 })
    }
  }
}

// MARK: - Fixtures

/// An `Animatable` modifier that dims its content and records the data its
/// body ran with.
private struct SiteFade: ViewModifier, Animatable {
  var progress: Double
  let log: AnimatableValueLog

  nonisolated var animatableData: Double {
    get { progress }
    set { progress = newValue }
  }

  func body(content: Content) -> some View {
    let _ = log.values.append(progress)
    content.opacity(0.25 + 0.75 * max(0, min(1, progress)))
  }
}

/// A body whose one site is a modifier around `content`.
private struct FadeSite: Transition {
  let log: AnimatableValueLog

  func body(content: Content, phase: TransitionPhase) -> some View {
    content.modifier(SiteFade(progress: phase.isIdentity ? 1 : 0, log: log))
  }
}

/// A view that conforms to `Animatable`.
private struct SiteBar: View, Animatable {
  var level: Double
  let log: AnimatableValueLog

  nonisolated var animatableData: Double {
    get { level }
    set { level = newValue }
  }

  var body: some View {
    let _ = log.secondary.append(level)
    Text(String(repeating: "#", count: max(0, min(4, Int((level * 4).rounded())))))
  }
}

/// A body with sites at three depths: two modifiers at the identity the body
/// resolves at, a view beside the content, and a view two stacks further in.
private struct DeepSites: Transition {
  let log: AnimatableValueLog

  func body(content: Content, phase: TransitionPhase) -> some View {
    let data: Double = phase.isIdentity ? 1 : 0
    HStack(spacing: 1) {
      content
      SiteBar(level: data, log: log)
      VStack(spacing: 0) {
        HStack(spacing: 0) {
          SiteBar(level: data, log: log)
        }
      }
    }
    .modifier(SiteFade(progress: data, log: log))
    .modifier(SiteFade(progress: data, log: log))
  }
}

/// One view under a body with a site, rendered through a renderer of its own
/// at fixed instants.
@MainActor
private final class SiteFrames {
  private static let animation = Animation.linear(duration: .milliseconds(800))
  private static let proposal = ProposedSize(width: .finite(30), height: .finite(3))

  let log = AnimatableValueLog()
  let renderer = DefaultRenderer()
  let start = MonotonicInstant(offset: .seconds(100))
  private let root: Identity

  init(named name: String) {
    root = testIdentity("body-site-engine", "frames", name)
  }

  var controller: AnimationController { renderer.internalAnimationController }

  /// The one live site of the body.
  var liveSite: AnimatableValueSite? {
    for identity in controller.debugStateSnapshot().previousIdentities {
      if let site = controller.valueSites(forIdentity: identity).first {
        return site
      }
    }
    return nil
  }

  /// The body state of the one removal in flight.
  var removalBody: RemovalBodyState? {
    controller.debugStateSnapshot().removingIdentities.lazy.compactMap {
      self.controller.removalBodyState(forIdentity: $0)
    }.first
  }

  func run(_ body: () throws -> Void) rethrows {
    try withAnimationSinks(controller) {
      controller.register(Self.animation)
      try body()
    }
  }

  func render(shown: Bool, animated: Bool = false, at offset: Int) {
    _ = renderer.renderArtifacts(
      SiteFramesHost(shown: shown, log: log),
      context: .init(identity: root, transaction: transaction(animated)),
      proposal: Self.proposal, frameInstant: start.advanced(by: .milliseconds(offset)))
  }

  func abort(shown: Bool, animated: Bool = false, at offset: Int) {
    let draft = renderer.prepareFrameHeadForCancellationTesting(
      SiteFramesHost(shown: shown, log: log),
      context: .init(identity: root, transaction: transaction(animated)),
      proposal: Self.proposal, frameInstant: start.advanced(by: .milliseconds(offset)))
    renderer.abortPreparedFrameHeadForCancellationTesting(draft)
  }

  private func transaction(_ animated: Bool) -> TransactionSnapshot {
    var transaction = TransactionSnapshot()
    if animated {
      transaction.animationRequest = .animate(Self.animation.animationBox)
    }
    return transaction
  }
}

private struct SiteFramesHost: View {
  let shown: Bool
  let log: AnimatableValueLog

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("HEADER")
      if shown {
        Text("PRESENT").transition(FadeSite(log: log))
      }
    }
  }
}
