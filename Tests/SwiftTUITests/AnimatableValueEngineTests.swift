import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIGraph
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// The engine under custom `Animatable` views, modifiers and shapes
/// (STUI-1546): how a conformer is found, how its site is named, what the
/// animation controller keeps for it, and the seams the transition engine
/// needs to animate a site inside a transition body.
///
/// These tests call the controller and the resolver directly, on package
/// API that the change adds.
@MainActor
@Suite("Animatable value engine", .serialized)
struct AnimatableValueEngineTests {
  private static let linear = Animation.linear(duration: .milliseconds(800))
  private static let start = MonotonicInstant(offset: .seconds(100))

  private static func instant(_ milliseconds: Int) -> MonotonicInstant {
    start.advanced(by: .milliseconds(milliseconds))
  }

  private static func animated(_ box: AnimationBox) -> TransactionSnapshot {
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(box)
    return transaction
  }

  // MARK: - Detection

  @Test("a type is a site when it, or the modifier it carries, has data to animate")
  func detectionClassifiesTypes() {
    typealias Detection = AnimatableSiteDetection
    #expect(Detection.kind(of: Text.self) == .none)
    #expect(Detection.kind(of: ModifiedContent<Text, EnginePlain>.self) == .none)
    #expect(Detection.kind(of: EngineGauge.self) == .view)
    #expect(Detection.kind(of: ModifiedContent<Text, EngineFade>.self) == .modifier)
    // Content and modifier both conform: the whole value is the site.
    #expect(Detection.kind(of: ModifiedContent<EngineGauge, EngineFade>.self) == .view)
    // `EmptyAnimatableData` is nothing to animate.
    #expect(Detection.kind(of: EngineNoData.self) == .none)
    #expect(Detection.kind(of: ModifiedContent<Text, EngineNoDataModifier>.self) == .none)
    // The answer is cached per type.
    #expect(Detection.kind(of: EngineGauge.self) == .view)

    #expect(Detection.isAnimatableShape(EngineWedge.self))
    #expect(Detection.isAnimatableShape(TrimmedShape<EngineWedge>.self))
    #expect(Detection.isAnimatableShape(InsetShape<EngineWedge>.self))
    #expect(Detection.isAnimatableShape(TrimmedShape<InsetShape<EngineWedge>>.self))
    #expect(!Detection.isAnimatableShape(Rectangle.self))
    #expect(!Detection.isAnimatableShape(TrimmedShape<Rectangle>.self))
  }

  @Test("a conformer that declares no data gets EmptyAnimatableData")
  func emptyDataIsTheDefault() {
    // `EngineNoData` declares no `animatableData`: the default supplies it.
    var value = EngineNoData()
    value.animatableData = EmptyAnimatableData()
    #expect(value.animatableData == EmptyAnimatableData())
  }

  // MARK: - Sites

  @Test("sites at one identity are named outer first, and the outermost conformer is the site")
  func sitesAreNamedOuterFirst() {
    let identity = testIdentity("animatable-engine", "sites")
    let sink = RecordingValueSink()
    AnimatableValueStorage.withSink(sink) {
      _ = Text("x").modifier(EngineFade(progress: 1)).modifier(EngineFade(progress: 2))
        .resolveElementsWork(in: .init(identity: identity)).run()
    }
    // Two modifiers at the identity of the text they wrap: the outer one is
    // position 0.
    #expect(
      sink.sites == [.init(identity: identity, ordinal: 0), .init(identity: identity, ordinal: 1)])
    #expect(sink.data == ["2.0", "1.0"])

    // A view and a modifier that both conform are one site with a pair for
    // data. The view inside is not asked for again.
    let pair = RecordingValueSink()
    AnimatableValueStorage.withSink(pair) {
      _ = EngineGauge(level: 3).modifier(EngineFade(progress: 4))
        .resolveElementsWork(in: .init(identity: identity)).run()
    }
    #expect(pair.sites == [.init(identity: identity, ordinal: 0)])
    #expect(pair.data == ["AnimatablePair<Double, Double>(first: 3.0, second: 4.0)"])

    // A view below another identity starts at position 0 again.
    let nested = RecordingValueSink()
    AnimatableValueStorage.withSink(nested) {
      _ = VStack { EngineGauge(level: 5) }.modifier(EngineFade(progress: 6))
        .resolveElementsWork(in: .init(identity: identity)).run()
    }
    #expect(nested.sites.count == 2)
    #expect(nested.sites.first == .init(identity: identity, ordinal: 0))
    #expect(nested.sites.last?.ordinal == 0)
    #expect(nested.sites.last?.identity != identity)
  }

  @Test("the sink's answer is what the body evaluates with, and the caller's value is untouched")
  func presentedDataReachesTheBody() {
    let identity = testIdentity("animatable-engine", "presented")
    let sink = RecordingValueSink()
    sink.override = 0.5
    let log = EngineLog()
    let view = Text("x").modifier(EngineFade(progress: 1, log: log))
    AnimatableValueStorage.withSink(sink) {
      _ = view.resolveElementsWork(in: .init(identity: identity)).run()
    }
    #expect(log.values == [0.5])
    #expect(view.modifier.progress == 1)

    // Without a sink a site evaluates with what the author wrote.
    _ = view.resolveElementsWork(in: .init(identity: identity)).run()
    #expect(log.values == [0.5, 1])
  }

  @Test("a transition phase evaluated outside the graph reads no sink")
  func scratchPhaseReadsNoSink() throws {
    let identity = testIdentity("animatable-engine", "scratch")
    let log = EngineLog()
    let renderer = DefaultRenderer()
    _ = renderer.renderArtifacts(
      Text("x").transition(AnyTransition(EngineBody(log: log))),
      context: .init(identity: identity), proposal: .init(width: .finite(10), height: .finite(2)))
    let registration = try #require(
      renderer.internalAnimationController.transitionBodyRegistration(forIdentity: identity))
    log.values.removeAll()

    let sink = RecordingValueSink()
    sink.override = 0.5
    AnimatableValueStorage.withSink(sink) {
      _ = registration.resolve(phase: .willAppear)
      _ = registration.resolve(phase: .didDisappear)
    }
    // The body's modifier ran with each phase's own data, and the sink that
    // was bound around the call was not asked.
    #expect(log.values == [0, 0])
    #expect(sink.sites.isEmpty)
  }

  @Test("a transition phase names the sites of its body as the live tree does")
  func scratchPhaseNamesTheLiveSites() throws {
    let identity = testIdentity("animatable-engine", "scratch-sites")
    let log = EngineLog()
    let renderer = DefaultRenderer()
    let controller = renderer.internalAnimationController
    // One `Animatable` modifier outside the transition and one inside its
    // body, all at the identity of the text.
    _ = renderer.renderArtifacts(
      Text("x").transition(AnyTransition(EngineBody(log: log)))
        .modifier(EngineFade(progress: 7)),
      context: .init(identity: identity), proposal: .init(width: .finite(10), height: .finite(2)))
    let live = controller.valueSites(forIdentity: identity)
    #expect(live == [.init(identity: identity, ordinal: 0), .init(identity: identity, ordinal: 1)])

    // A caller that supplies a sink is asked for the body's site under the
    // name it has in the live tree, and its answer is what the body gets.
    let registration = try #require(controller.transitionBodyRegistration(forIdentity: identity))
    let sink = RecordingValueSink()
    sink.override = 0.5
    log.values.removeAll()
    _ = registration.resolve(phase: .willAppear, valueSink: sink)
    #expect(sink.sites == [.init(identity: identity, ordinal: 1)])
    #expect(sink.data == ["0.0"])
    #expect(log.values == [0.5])
    // The live controller's records are as they were.
    #expect(controller.valueSites(forIdentity: identity) == live)
  }

  // MARK: - The controller

  @Test("a site's first target is recorded, and a change under an animation starts from it")
  func pullStartsFromTheRecordedTarget() {
    let controller = AnimationController()
    let box = controller.register(Self.linear)
    let site = AnimatableValueSite(identity: testIdentity("animatable-engine", "pull"), ordinal: 0)
    func pull(_ target: Double, _ transaction: TransactionSnapshot = .init()) -> Double {
      controller.presentedAnimatableData(
        for: target, at: site, transaction: transaction, reducesMotion: false)
    }

    #expect(controller.beginValueSiteFrame(at: Self.instant(0)).isEmpty)
    // First resolve: nothing to animate from, even under an animation.
    #expect(pull(0, Self.animated(box)) == 0)
    #expect(controller.activeValueAnimationCount == 0)
    #expect(controller.valueSites(forIdentity: site.identity) == [site])

    // The target changes under an animation: the body gets the origin.
    #expect(pull(1, Self.animated(box)) == 0)
    #expect(controller.activeValueAnimationCount == 1)
    #expect(controller.valueAnimationSites(forIdentity: site.identity) == [site])
    // Every resolve of the frame agrees, whatever transaction it carries.
    #expect(pull(1, Self.animated(box)) == 0)
    #expect(pull(1) == 0)

    // The head samples once per frame and names the owner.
    #expect(controller.beginValueSiteFrame(at: Self.instant(400)) == [site.identity])
    #expect(abs(pull(1) - 0.5) < 1e-9)
    #expect(abs(pull(1) - 0.5) < 1e-9)

    // The frame that ends the animation names the owner once more, and the
    // site resolves with its target.
    #expect(controller.beginValueSiteFrame(at: Self.instant(800)) == [site.identity])
    #expect(pull(1) == 1)
    #expect(controller.activeValueAnimationCount == 0)
    #expect(controller.beginValueSiteFrame(at: Self.instant(833)).isEmpty)
    #expect(pull(1) == 1)
  }

  @Test("a change without an animation ends the animation in flight")
  func pullWithoutAnAnimationSnaps() {
    let controller = AnimationController()
    let box = controller.register(Self.linear)
    let site = AnimatableValueSite(identity: testIdentity("animatable-engine", "snap"), ordinal: 0)
    func pull(
      _ target: Double, _ transaction: TransactionSnapshot = .init(), reducesMotion: Bool = false
    ) -> Double {
      controller.presentedAnimatableData(
        for: target, at: site, transaction: transaction, reducesMotion: reducesMotion)
    }
    _ = controller.beginValueSiteFrame(at: Self.instant(0))
    _ = pull(0)
    #expect(pull(1, Self.animated(box)) == 0)

    // A plain write in flight: the value goes to the new target at once.
    _ = controller.beginValueSiteFrame(at: Self.instant(400))
    #expect(pull(3) == 3)
    #expect(controller.activeValueAnimationCount == 0)

    // Reduced motion wins over the transaction's animation.
    #expect(pull(4, Self.animated(box), reducesMotion: true) == 4)
    #expect(controller.activeValueAnimationCount == 0)

    // A disabled transaction snaps as well.
    var disabled = TransactionSnapshot()
    disabled.animationRequest = .disabled
    #expect(pull(5, disabled) == 5)
    #expect(controller.activeValueAnimationCount == 0)
  }

  @Test("reduced motion ends the animation in flight at its target, where the body runs")
  func reducedMotionSettlesInFlight() {
    let controller = AnimationController()
    let box = controller.register(Self.linear)
    let identity = testIdentity("animatable-engine", "settle")
    let site = AnimatableValueSite(identity: identity, ordinal: 0)
    func pull(
      _ target: Double, _ transaction: TransactionSnapshot = .init(), reducesMotion: Bool = false
    ) -> Double {
      controller.presentedAnimatableData(
        for: target, at: site, transaction: transaction, reducesMotion: reducesMotion)
    }
    var style = StyleEnvironmentSnapshot()
    style.stableOutput = true
    let reduced = ResolvedNode(
      identity: identity, kind: .view(.text), environmentSnapshot: .init(style: style))
    _ = controller.beginValueSiteFrame(at: Self.instant(0))
    _ = pull(0)
    controller.processResolvedTree(
      ResolvedNode(identity: identity, kind: .view(.text)), transaction: .init(),
      timestamp: Self.instant(0))
    #expect(pull(1, Self.animated(box)) == 0)

    // A transaction that disables animations says how a change is applied.
    // Nothing changed, so the animation in flight goes on.
    _ = controller.beginValueSiteFrame(at: Self.instant(400))
    var disabled = TransactionSnapshot()
    disabled.animationRequest = .disabled
    #expect(abs(pull(1, disabled) - 0.5) < 1e-9)
    #expect(controller.activeValueAnimationCount == 1)

    // The policy sweep over the tree does not end a value animation: the
    // body would stay at the sample it last ran with.
    controller.processResolvedTree(reduced, transaction: .init(), timestamp: Self.instant(400))
    #expect(controller.activeValueAnimationCount == 1)

    // The site ends it when it resolves under the policy, and presents its
    // target. Every later resolve of the frame agrees.
    #expect(controller.beginValueSiteFrame(at: Self.instant(433)) == [identity])
    #expect(pull(1, reducesMotion: true) == 1)
    #expect(controller.activeValueAnimationCount == 0)
    #expect(pull(1, reducesMotion: true) == 1)
    #expect(pull(1) == 1)
    #expect(controller.beginValueSiteFrame(at: Self.instant(466)).isEmpty)
  }

  @Test("writes under tracksVelocity release their velocity into the spring that follows")
  func trackedWritesSeedTheSpring() {
    let controller = AnimationController()
    let spring = Animation.spring(duration: .milliseconds(600), bounce: 0.2)
    let box = controller.register(spring)
    let site = AnimatableValueSite(
      identity: testIdentity("animatable-engine", "velocity"), ordinal: 0)
    var tracked = TransactionSnapshot()
    tracked.tracksVelocity = true
    func pull(_ target: Double, _ transaction: TransactionSnapshot) -> Double {
      controller.presentedAnimatableData(
        for: target, at: site, transaction: transaction, reducesMotion: false)
    }
    _ = controller.beginValueSiteFrame(at: Self.instant(0))
    _ = pull(0, .init())
    // A drag writes the value frame by frame. Each write snaps, and is
    // sampled.
    for (milliseconds, value) in [(33, 0.1), (66, 0.2), (99, 0.3)] {
      _ = controller.beginValueSiteFrame(at: Self.instant(milliseconds))
      #expect(pull(value, tracked) == value)
    }
    #expect(controller.velocitySamplerCount == 1)
    // The release animates on from where the drag left the value, with the
    // drag's velocity along the new axis.
    _ = controller.beginValueSiteFrame(at: Self.instant(132))
    #expect(pull(1, Self.animated(box)) == 0.3)
    let velocity = controller.valueAnimationInitialVelocity(at: site)
    #expect((velocity ?? 0) > 0, "\(String(describing: velocity))")
    #expect(controller.velocitySamplerCount == 0)

    // A retarget carries the velocity of the curve in flight.
    _ = controller.beginValueSiteFrame(at: Self.instant(165))
    let moving = pull(1, .init())
    #expect(moving > 0.3)
    #expect(pull(2, Self.animated(box)) == moving)
    #expect((controller.valueAnimationInitialVelocity(at: site) ?? 0) > 0)
  }

  @Test("a value animation can start from a supplied origin")
  func animationStartsFromASuppliedOrigin() {
    let controller = AnimationController()
    let box = controller.register(Self.linear)
    let identity = testIdentity("animatable-engine", "origin")
    let site = AnimatableValueSite(identity: identity, ordinal: 2)
    func boxed<Data: VectorArithmetic>(_ data: Data) -> AnyAnimatable {
      AnimationController.boxedAnimatableData(data)
    }

    // Before any frame there is no instant to start at.
    #expect(
      !controller.beginValueAnimation(
        at: site, from: boxed(0.25), to: boxed(1.0), animationBox: box, batchID: nil))

    _ = controller.beginValueSiteFrame(at: Self.instant(0))
    #expect(
      controller.beginValueAnimation(
        at: site, from: boxed(0.25), to: boxed(1.0), animationBox: box, batchID: nil))
    // The site never resolved with 0.25. Its resolve with the target on the
    // same frame reads the origin, as an insertion from another phase needs.
    func pull() -> Double {
      controller.presentedAnimatableData(
        for: 1.0, at: site, transaction: .init(), reducesMotion: false)
    }
    #expect(pull() == 0.25)
    #expect(controller.valueAnimationSample(at: site) == boxed(0.25))
    #expect(controller.valueAnimationSites(forIdentity: identity) == [site])

    #expect(controller.beginValueSiteFrame(at: Self.instant(400)) == [identity])
    #expect(abs(pull() - 0.625) < 1e-9)

    // Data of another type cannot interpolate, so nothing starts.
    #expect(
      !controller.beginValueAnimation(
        at: site, from: boxed(0.25), to: boxed(AnimatablePair(1.0, 2.0)), animationBox: box,
        batchID: nil))
  }

  @Test("value animations ride the frame draft and the checkpoint")
  func valueAnimationsRideTheDraft() {
    let controller = AnimationController()
    let box = controller.register(Self.linear)
    let site = AnimatableValueSite(identity: testIdentity("animatable-engine", "draft"), ordinal: 0)
    func pull(
      on controller: AnimationController, _ target: Double,
      _ transaction: TransactionSnapshot = .init()
    ) -> Double {
      controller.presentedAnimatableData(
        for: target, at: site, transaction: transaction, reducesMotion: false)
    }
    _ = controller.beginValueSiteFrame(at: Self.instant(0))
    _ = pull(on: controller, 0)

    // A draft that starts the animation and is discarded leaves the live
    // controller as it was: no animation, and the old target on record.
    let discarded = controller.makeFrameDraft()
    _ = discarded.controller.beginValueSiteFrame(at: Self.instant(0))
    #expect(pull(on: discarded.controller, 1, Self.animated(box)) == 0)
    #expect(discarded.controller.activeValueAnimationCount == 1)
    discarded.discard()
    #expect(controller.activeValueAnimationCount == 0)

    // A committed draft publishes it.
    let committed = controller.makeFrameDraft()
    _ = committed.controller.beginValueSiteFrame(at: Self.instant(0))
    #expect(pull(on: committed.controller, 1, Self.animated(box)) == 0)
    committed.commit()
    #expect(controller.activeValueAnimationCount == 1)

    // A tick that is discarded does not advance the live animation, and a
    // later tick lands on its own instant.
    let dropped = controller.makeFrameDraft()
    #expect(dropped.controller.beginValueSiteFrame(at: Self.instant(400)) == [site.identity])
    #expect(abs(pull(on: dropped.controller, 1) - 0.5) < 1e-9)
    dropped.discard()
    let next = controller.makeFrameDraft()
    _ = next.controller.beginValueSiteFrame(at: Self.instant(600))
    #expect(abs(pull(on: next.controller, 1) - 0.75) < 1e-9)
    next.commit()

    // An aborted frame-head transaction restores the animation it ended.
    let checkpoint = controller.beginFrameHeadTransaction()
    _ = controller.beginValueSiteFrame(at: Self.instant(700))
    #expect(pull(on: controller, 9) == 9)
    #expect(controller.activeValueAnimationCount == 0)
    controller.abortFrameHeadTransaction(checkpoint)
    #expect(controller.activeValueAnimationCount == 1)
    _ = controller.beginValueSiteFrame(at: Self.instant(800))
    #expect(pull(on: controller, 1) == 1)
  }

  @Test("a site's record and its animation leave with its identity")
  func recordsLeaveWithTheirIdentity() {
    let controller = AnimationController()
    let box = controller.register(Self.linear)
    let root = testIdentity("animatable-engine", "leave")
    let owner = root.child(.named("owner"))
    let site = AnimatableValueSite(identity: owner, ordinal: 0)
    func tree(present: Bool) -> ResolvedNode {
      ResolvedNode(
        identity: root, kind: .view(.group),
        children: present ? [ResolvedNode(identity: owner, kind: .view(.text))] : [])
    }
    func pull(_ target: Double, _ transaction: TransactionSnapshot = .init()) -> Double {
      controller.presentedAnimatableData(
        for: target, at: site, transaction: transaction, reducesMotion: false)
    }
    _ = controller.beginValueSiteFrame(at: Self.instant(0))
    _ = pull(0)
    controller.processResolvedTree(
      tree(present: true), transaction: .init(), timestamp: Self.instant(0))
    #expect(controller.valueSiteCount == 1)
    #expect(pull(1, Self.animated(box)) == 0)
    #expect(controller.activeValueAnimationCount == 1)

    // The view leaves: its animation ends and its record goes.
    controller.processResolvedTree(
      tree(present: false), transaction: .init(), timestamp: Self.instant(33))
    #expect(controller.activeValueAnimationCount == 0)
    #expect(controller.valueSiteCount == 0)

    // A view that appears there later is a new view: it starts from its own
    // value, even under an animation.
    _ = controller.beginValueSiteFrame(at: Self.instant(66))
    #expect(pull(5, Self.animated(box)) == 5)
    #expect(controller.activeValueAnimationCount == 0)
  }

  @Test("a value animation keeps frames coming and is never elided")
  func valueAnimationBlocksElision() {
    let controller = AnimationController()
    let box = controller.register(Self.linear)
    let identity = testIdentity("animatable-engine", "elision")
    let site = AnimatableValueSite(identity: identity, ordinal: 0)
    var tree = ResolvedNode(identity: identity, kind: .view(.text))
    _ = controller.beginValueSiteFrame(at: Self.instant(0))
    _ = controller.presentedAnimatableData(
      for: 0.0, at: site, transaction: .init(), reducesMotion: false)
    #expect(!controller.blocksOffscreenFrameElision)
    _ = controller.presentedAnimatableData(
      for: 1.0, at: site, transaction: Self.animated(box), reducesMotion: false)

    #expect(controller.hasValueAnimation)
    #expect(controller.blocksOffscreenFrameElision)
    #expect(!controller.hasPlacedPassOwnedAnimationWork)
    #expect(controller.preFrameHeadOffscreenPropertyAnimationRedrawIdentities == nil)
    #expect(controller.requiresContinuedAnimationFrames)
    // It asks for the next tick and reports nothing to redraw: its owner is
    // invalidated instead, and nothing is written to the tree.
    let before = tree
    let tick = controller.applyInterpolations(to: &tree, at: Self.instant(0))
    #expect(tick.hasPendingWork)
    #expect(tick.nextDeadline == Self.instant(33))
    #expect(tick.redrawIdentities.isEmpty)
    #expect(tree == before)
    // The count of property animations does not include it.
    #expect(controller.activeAnimationCount == 0)
  }

  @Test("the owner of a ticked value animation takes the frame's transaction")
  func tickedOwnerTakesTheFramesTransaction() {
    let root = testIdentity("animatable-engine", "ticked")
    let owner = root.child(.named("owner"))
    // The parent was resolved under an animation on an earlier frame and
    // still carries its request. The owner is resolved again on every tick.
    func tree(opacity: Double, parent: TransactionSnapshot) -> ResolvedNode {
      ResolvedNode(
        identity: root, kind: .view(.group),
        children: [
          ResolvedNode(
            identity: owner, kind: .view(.text),
            drawMetadata: .init(opacity: opacity))
        ],
        transactionSnapshot: parent)
    }
    for ticks in [false, true] {
      let controller = AnimationController()
      let box = controller.register(Self.linear)
      let site = AnimatableValueSite(identity: owner, ordinal: 0)
      _ = controller.beginValueSiteFrame(at: Self.instant(0))
      _ = controller.presentedAnimatableData(
        for: 0.0, at: site, transaction: .init(), reducesMotion: false)
      controller.processResolvedTree(
        tree(opacity: 0, parent: .init()), transaction: .init(), timestamp: Self.instant(0))
      if ticks {
        _ = controller.presentedAnimatableData(
          for: 1.0, at: site, transaction: Self.animated(box), reducesMotion: false)
      }
      // The next frame: the owner's body produced another opacity.
      let owners = controller.beginValueSiteFrame(at: Self.instant(33))
      #expect(owners == (ticks ? [owner] : []))
      controller.processResolvedTree(
        tree(opacity: 0.5, parent: Self.animated(box)), transaction: .init(),
        timestamp: Self.instant(33))
      // Without a tick the owner inherits its parent's request and its
      // opacity animates. With one it does not: the sample is written as it
      // is, and the value animation is the only animation.
      #expect(controller.activeAnimationCount == (ticks ? 0 : 1))
    }
  }

  // MARK: - Shapes

  @Test("a fill, a stroke and a clip of an Animatable shape record its data")
  func shapeModifiersRecordTheData() throws {
    let context = ResolveContext(identity: testIdentity("animatable-engine", "shape"))
    let log = EngineLog()
    let fill = try #require(
      EngineWedge(fraction: 0.25, log: log).fill(Color.white)
        .resolveElementsWork(in: context).run().first)
    let stroke = try #require(
      EngineWedge(fraction: 0.25, log: log).stroke(Color.white)
        .resolveElementsWork(in: context).run().first)
    let clip = try #require(
      Text("x").clipShape(EngineWedge(fraction: 0.25, log: log))
        .resolveElementsWork(in: context).run().first)
    let bare = try #require(
      EngineWedge(fraction: 0.25, log: log).trim(from: 0, to: 0.5)
        .resolveElementsWork(in: context).run().first)

    // The data is its own slot, and a shape that has one does not morph.
    for node in [fill, stroke, bare] {
      let snapshot = AnimatableSnapshot.extract(from: node)
      #expect(snapshot[.shapeData] != nil)
      #expect(snapshot[.shapePath] == nil)
    }
    let clipSnapshot = AnimatableSnapshot.extract(from: clip)
    #expect(clipSnapshot[.clipShapeData(0)] != nil)
    #expect(clipSnapshot[.clipShapePaths] == nil)

    // A shape that does not conform keeps the path slots.
    let plain = try #require(
      EnginePlainWedge(fraction: 0.25).fill(Color.white)
        .resolveElementsWork(in: context).run().first)
    #expect(AnimatableSnapshot.extract(from: plain)[.shapeData] == nil)
    #expect(AnimatableSnapshot.extract(from: plain)[.shapePath] != nil)
    let plainClip = try #require(
      Text("x").clipShape(EnginePlainWedge(fraction: 0.25))
        .resolveElementsWork(in: context).run().first)
    #expect(AnimatableSnapshot.extract(from: plainClip)[.clipShapeData(0)] == nil)
    #expect(AnimatableSnapshot.extract(from: plainClip)[.clipShapePaths] != nil)

    // Two clips on one view: each keeps its own way of animating.
    let mixed = try #require(
      Text("x").clipShape(EnginePlainWedge(fraction: 0.25))
        .clipShape(EngineWedge(fraction: 0.25, log: log))
        .resolveElementsWork(in: context).run().first)
    let mixedSnapshot = AnimatableSnapshot.extract(from: mixed)
    #expect(mixedSnapshot[.clipShapeData(1)] != nil)
    #expect(mixedSnapshot[.clipShapeData(0)] == nil)
    #expect(mixedSnapshot[.clipShapePaths]?.unwrap(as: ClipMaskPaths.self)?.paths.count == 2)
  }

  @Test("a sample of a shape's data is evaluated by the destination's shape")
  func shapeSamplesUseTheDestination() throws {
    let log = EngineLog()
    let from = try #require(
      EngineWedge(fraction: 0, mark: 1, log: log).animatableShapeProvider(fills: true))
    let to = try #require(
      EngineWedge(fraction: 1, mark: 2, log: log).animatableShapeProvider(fills: true))
    // Equal data of one shape type is an equal value, whatever else differs.
    let same = try #require(
      EngineWedge(fraction: 1, mark: 3, log: log).animatableShapeProvider(fills: true))
    #expect(to == same)
    #expect(from != to)
    #expect(EnginePlainWedge(fraction: 1).animatableShapeProvider(fills: true) == nil)

    func erase<Value: AnimatableShapeValue>(_ value: Value) -> AnyAnimatable {
      AnyAnimatable(value)
    }
    log.values.removeAll()
    log.marks.removeAll()
    let sample = AnimationPropertyValueApplication.interpolate(
      from: erase(from.value), to: erase(to.value), progress: 0.25)
    // Interpolating evaluates nothing. The geometry is asked for once, when
    // the sample is turned into what a node is written with.
    #expect(log.values.isEmpty)
    let presented = AnimationPropertyValueApplication.presentationValue(of: sample, for: .shapeData)
    #expect(log.values == [0.25])
    #expect(log.marks == [2])
    let geometry = try #require(presented.unwrap(as: SampledShapeGeometry.self)?.geometry)
    #expect(geometry == EngineWedge(fraction: 0.25, mark: 2, log: EngineLog()).geometry)
    // A sample of any other slot is written as it is.
    let opacity = AnyAnimatable(0.5)
    #expect(
      AnimationPropertyValueApplication.presentationValue(of: opacity, for: .opacity) == opacity)
  }
}

// MARK: - Fixtures

@MainActor
private final class EngineLog {
  var values: [Double] = []
  var marks: [Int] = []
}

/// Records what the resolver asks for and answers with the target, or with
/// `override` for `Double` data.
@MainActor
private final class RecordingValueSink: AnimatableValueSink {
  var sites: [AnimatableValueSite] = []
  var data: [String] = []
  var override: Double?

  func presentedAnimatableData<Data: VectorArithmetic>(
    for target: Data,
    at site: AnimatableValueSite,
    ownerNodeID: ViewNodeID?,
    transaction: TransactionSnapshot,
    reducesMotion: Bool
  ) -> Data {
    sites.append(site)
    data.append("\(target)")
    if let override, let presented = override as? Data {
      return presented
    }
    return target
  }
}

private struct EngineFade: ViewModifier, Animatable {
  var progress: Double
  var log: EngineLog?

  nonisolated var animatableData: Double {
    get { progress }
    set { progress = newValue }
  }

  func body(content: Content) -> some View {
    let _ = log?.values.append(progress)
    content.opacity(max(0, min(1, progress)))
  }
}

private struct EnginePlain: ViewModifier {
  func body(content: Content) -> some View {
    content
  }
}

private struct EngineGauge: View, Animatable {
  var level: Double

  nonisolated var animatableData: Double {
    get { level }
    set { level = newValue }
  }

  var body: some View {
    Text("\(level)")
  }
}

/// A view that conforms and declares no data.
private struct EngineNoData: View, Animatable {
  var body: some View {
    Text("x")
  }
}

private struct EngineNoDataModifier: ViewModifier, Animatable {
  func body(content: Content) -> some View {
    content
  }
}

private struct EngineWedge: InsettableShape, Animatable {
  var fraction: Double
  var mark = 0
  let log: EngineLog

  nonisolated var animatableData: Double {
    get { fraction }
    set { fraction = newValue }
  }

  func path(in rect: Rect) -> Path {
    log.values.append(fraction)
    log.marks.append(mark)
    return Path(
      Rect(
        origin: rect.origin, size: Size(width: rect.size.width * fraction, height: rect.size.height)
      ))
  }
}

private struct EnginePlainWedge: Shape {
  var fraction: Double

  func path(in rect: Rect) -> Path {
    Path(
      Rect(
        origin: rect.origin, size: Size(width: rect.size.width * fraction, height: rect.size.height)
      ))
  }
}

/// A transition whose body applies an `Animatable` modifier.
private struct EngineBody: Transition {
  let log: EngineLog

  func body(content: Content, phase: TransitionPhase) -> some View {
    content.modifier(EngineFade(progress: phase.isIdentity ? 1 : 0, log: log))
  }
}
