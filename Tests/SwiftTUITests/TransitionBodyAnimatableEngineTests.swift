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

  // MARK: - A registration another node declared

  @Test("a registration another node declared follows what its own node emits")
  func registrationFollowsWhatItsNodeEmits() throws {
    let controller = AnimationController()
    controller.register(Self.linear)
    let host = testIdentity("body-site-engine", "declared")
    let shown = host.child(.named("true"))
    let other = host.child(.named("false"))
    let declaring = ViewNodeID(rawValue: 1)
    let member = ViewNodeID(rawValue: 2)
    let start = MonotonicInstant(offset: .seconds(50))
    var animated = TransactionSnapshot()
    animated.animationRequest = .animate(Self.linear.animationBox)
    func tree(_ identity: Identity) -> ResolvedNode {
      ResolvedNode(
        viewNodeID: declaring,
        identity: host,
        kind: .view(.vStack),
        children: [
          ResolvedNode(
            viewNodeID: member, identity: identity, kind: .view(.text), drawPayload: .text("X"))
        ])
    }

    // The node above declares the transition for the node below, which has
    // a graph node of its own.
    controller.beginTransitionCollection()
    controller.registerTransition(
      for: shown, viewNodeID: member, declaringNodeID: declaring, transition: AnyTransition.opacity)
    controller.finishTransitionCollection(reEvaluatedNodeIDs: [declaring, member])
    controller.processResolvedTree(tree(shown), transaction: .init(), timestamp: start)
    #expect(controller.debugStateSnapshot().transitionIdentities == [shown])

    // The node below runs alone and still emits the identity that was
    // registered. The modifier did not run, and the registration stands.
    controller.beginTransitionCollection()
    controller.finishTransitionCollection(reEvaluatedNodeIDs: [member])
    controller.processResolvedTree(
      tree(shown), transaction: .init(), timestamp: start.advanced(by: .milliseconds(33)))
    #expect(controller.debugStateSnapshot().transitionIdentities == [shown])
    #expect(controller.debugStateSnapshot().removingIdentities.isEmpty)

    // It runs alone again and now emits another identity. The registration
    // was for the view that left: that view plays its exit, and the
    // registration goes.
    controller.beginTransitionCollection()
    controller.finishTransitionCollection(reEvaluatedNodeIDs: [member])
    controller.processResolvedTree(
      tree(other), transaction: animated, timestamp: start.advanced(by: .milliseconds(66)))
    let state = controller.debugStateSnapshot()
    #expect(state.removingIdentities == [shown])
    #expect(!state.transitionIdentities.contains(shown))
    #expect(state.transitionNodeIDs.isEmpty)
  }

  @Test("a registration goes when the node that declared it has left the graph")
  func registrationOfADepartedDeclarationIsDropped() {
    let host = testIdentity("body-site-engine", "departed-declaration")
    let shown = host.child(.named("item"))
    let declaring = ViewNodeID(rawValue: 1)
    let member = ViewNodeID(rawValue: 2)
    let unrelated: Set<ViewNodeID> = [ViewNodeID(rawValue: 9)]
    let start = MonotonicInstant(offset: .seconds(50))
    // The registered node stays in the tree throughout and never runs again.
    let tree = ResolvedNode(
      viewNodeID: ViewNodeID(rawValue: 3),
      identity: host,
      kind: .view(.vStack),
      children: [
        ResolvedNode(
          viewNodeID: member, identity: shown, kind: .view(.text), drawPayload: .text("X"))
      ])
    func registered() -> AnimationController {
      let controller = AnimationController()
      controller.beginTransitionCollection()
      controller.registerTransition(
        for: shown, viewNodeID: member, declaringNodeID: declaring,
        transition: AnyTransition.opacity)
      controller.finishTransitionCollection(
        reEvaluatedNodeIDs: [declaring, member], isLiveNode: { _ in true })
      controller.processResolvedTree(tree, transaction: .init(), timestamp: start)
      return controller
    }

    // The declaring node is in the graph and did not run: the registration
    // stands.
    let kept = registered()
    kept.beginTransitionCollection()
    kept.finishTransitionCollection(reEvaluatedNodeIDs: unrelated, isLiveNode: { _ in true })
    #expect(kept.debugStateSnapshot().transitionIdentities == [shown])

    // The declaring node has left the graph, and its modifier with it.
    let dropped = registered()
    dropped.beginTransitionCollection()
    dropped.finishTransitionCollection(
      reEvaluatedNodeIDs: unrelated, isLiveNode: { $0 != declaring })
    #expect(dropped.debugStateSnapshot().transitionIdentities.isEmpty)
    #expect(dropped.debugStateSnapshot().transitionNodeIDs.isEmpty)
    // The frame before still knows it, for a removal on this frame.
    #expect(dropped.debugStateSnapshot().previousTransitionIdentities == [shown])

    // A caller that cannot say which nodes are in the graph drops nothing
    // for it.
    let unknown = registered()
    unknown.beginTransitionCollection()
    unknown.finishTransitionCollection(reEvaluatedNodeIDs: unrelated)
    #expect(unknown.debugStateSnapshot().transitionIdentities == [shown])
  }

  // MARK: - A site's record

  @Test("a site is live until the node that evaluates it runs without resolving it")
  func siteLivenessFollowsItsOwnersEvaluation() {
    let host = testIdentity("body-site-engine", "liveness")
    let inline = AnimationKey(
      site: AnimatableValueSite(identity: host.child(.named("inline")), ordinal: 0))
    let beside = AnimationKey(
      site: AnimatableValueSite(identity: host.child(.named("beside")), ordinal: 0))
    let late = AnimationKey(
      site: AnimatableValueSite(identity: host.child(.named("late")), ordinal: 0))
    let slot = ViewNodeID(rawValue: 7)
    let other = ViewNodeID(rawValue: 8)
    // None of the three identities is in the tree: each site is known by the
    // node that evaluates it, and both nodes stay in the tree throughout.
    let liveNodeIDs: Set<ViewNodeID> = [slot, other]
    func isLive(_ key: AnimationKey, in sites: AnimationController.ValueSiteState) -> Bool {
      sites.isLive(key, identities: [], liveNodeIDs: liveNodeIDs)
    }
    func resolved() -> AnimationController.ValueSiteState {
      var sites = AnimationController.ValueSiteState()
      // Two sites resolve while the head resolves, one for each node. The
      // third resolves afterwards, as a view does that resolves in layout.
      sites.beginHeadResolve()
      sites.ownerNodeIDs = [inline: slot, beside: other]
      sites.noteResolve(of: inline)
      sites.noteResolve(of: beside)
      sites.finishHeadResolve(reEvaluatedNodeIDs: [slot, other])
      sites.ownerNodeIDs[late] = slot
      sites.noteResolve(of: late)
      return sites
    }

    var sites = resolved()
    #expect(isLive(inline, in: sites) && isLive(beside, in: sites) && isLive(late, in: sites))

    // The slot's node runs again and resolves neither of its sites: the
    // view at the first site left, and the slot kept its node. The site
    // that resolves outside the head is not judged by that: nothing says it
    // would have resolved by now. The other node did not run.
    sites.beginHeadResolve()
    sites.finishHeadResolve(reEvaluatedNodeIDs: [slot])
    #expect(!isLive(inline, in: sites))
    #expect(isLive(late, in: sites))
    #expect(isLive(beside, in: sites))

    // The node runs and resolves its site: the site stays.
    sites = resolved()
    sites.beginHeadResolve()
    sites.noteResolve(of: inline)
    sites.finishHeadResolve(reEvaluatedNodeIDs: [slot])
    #expect(isLive(inline, in: sites))

    // A frame that evaluates nothing judges no site, and one that evaluates
    // everything judges every site that resolves in the head.
    sites = resolved()
    sites.beginHeadResolve()
    sites.finishHeadResolve(reEvaluatedNodeIDs: [])
    #expect(isLive(inline, in: sites) && isLive(beside, in: sites))
    sites.beginHeadResolve()
    sites.finishHeadResolve(reEvaluatedNodeIDs: nil)
    #expect(!isLive(inline, in: sites) && !isLive(beside, in: sites))
    #expect(isLive(late, in: sites))

    // A site that later resolves in the head is judged like any other.
    sites = resolved()
    sites.beginHeadResolve()
    sites.noteResolve(of: late)
    sites.finishHeadResolve(reEvaluatedNodeIDs: [slot])
    #expect(isLive(late, in: sites))
    sites.beginHeadResolve()
    sites.finishHeadResolve(reEvaluatedNodeIDs: [slot])
    #expect(!isLive(late, in: sites))
  }

  // MARK: - The root that holds a site

  @Test("a site is held by the first root of the body that it is part of")
  func holderOfASite() {
    let body = testIdentity("body-site-engine", "holders")
    func node(_ identity: Identity, _ children: [ResolvedNode] = []) -> ResolvedNode {
      ResolvedNode(identity: identity, kind: .view(.vStack), children: children)
    }
    let first = body.child(.named("first"))
    let second = body.child(.named("second"))
    let third = body.child(.named("third"))
    // A view of the second root whose body root is a conditional: only its
    // branch is in the tree.
    let branching = second.child(.named("gauge"))
    let holders = TransitionBodySiteHolders(roots: [
      node(first, [node(first.child(.named("content")))]),
      node(second, [node(branching.child(.named("true")))]),
      node(third),
    ])
    // A modifier around a root's view, and a view inside a root.
    #expect(holders.holderIndex(ofSiteAt: first) == 0)
    #expect(holders.holderIndex(ofSiteAt: second) == 1)
    #expect(holders.holderIndex(ofSiteAt: first.child(.named("content"))) == 0)
    // A view whose own identity is not in the tree, and a view that draws
    // nothing, belong to the root they lie in.
    #expect(holders.holderIndex(ofSiteAt: branching) == 1)
    #expect(holders.holderIndex(ofSiteAt: third.child(.named("silent"))) == 2)
    // A site above every root is held by the first, and is part of each.
    #expect(holders.holderIndex(ofSiteAt: body) == 0)
    #expect((0..<3).allSatisfy { holders.reaches(body, rootAt: $0) })
    // A site that is part of no root is held by the first and is part of
    // none.
    let elsewhere = testIdentity("body-site-engine", "elsewhere")
    #expect(holders.holderIndex(ofSiteAt: elsewhere) == 0)
    #expect((0..<3).allSatisfy { !holders.reaches(elsewhere, rootAt: $0) })
    // A site one root holds is not part of the others.
    #expect(!holders.reaches(first, rootAt: 1) && !holders.reaches(second, rootAt: 0))
    // A body with no root holds nothing.
    #expect(TransitionBodySiteHolders(roots: []).holderIndex(ofSiteAt: body) == nil)
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
