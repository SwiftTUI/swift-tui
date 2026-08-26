import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@Suite("OffscreenFrameElisionRuntime", .serialized)
@MainActor
struct OffscreenFrameElisionRuntimeTests {
  @Test("freshly-constructed renderer reports empty previousDrawnIdentities")
  func freshRendererHasEmptyPreviousDrawnIdentities() {
    let renderer = DefaultRenderer()
    #expect(renderer.frameTailRenderer.previousDrawnIdentities.isEmpty)
  }

  @Test("elidedFrameCount starts at zero")
  func elidedFrameCountStartsZero() {
    let renderer = DefaultRenderer()
    #expect(renderer.elidedFrameCount == 0)
  }

  @Test("previousDrawnIdentities reflects the set stored by storeCommittedFrame")
  func previousDrawnIdentitiesRoundTrips() {
    let retainedState = FrameTailRetainedState()
    let expected: Set<Identity> = [testIdentity("A"), testIdentity("B")]
    let identity = testIdentity("Root")
    let placed = PlacedNode(identity: identity, bounds: .init(origin: .zero, size: .zero))
    let artifacts = FrameArtifacts(
      resolvedTree: ResolvedNode(identity: identity, kind: .root),
      measuredTree: MeasuredNode(
        identity: identity,
        proposal: .unspecified,
        measuredSize: .zero
      ),
      placedTree: placed,
      semanticSnapshot: .init(),
      drawTree: DrawNode(identity: identity, bounds: .init(origin: .zero, size: .zero)),
      rasterSurface: .init(),
      presentationDamage: nil,
      drawnIdentities: expected,
      commitPlan: CommitPlan(
        transaction: .init(), semanticSnapshot: .init(), lifecycle: [], handlerInstallations: []),
      diagnostics: .init()
    )
    retainedState.storeCommittedFrame(
      artifacts,
      baselinePlacedTree: placed,
      proposal: .unspecified
    )
    #expect(retainedState.previousDrawnIdentities == expected)
  }

  @Test("retained phase products round trip only for baseline-matching placed trees")
  func retainedPhaseProductsRequireBaselineMatchingPlacedTree() {
    let retainedState = FrameTailRetainedState()
    let identity = testIdentity("Root")
    let baseline = PlacedNode(identity: identity, bounds: .init(origin: .zero, size: .zero))
    let semantics = SemanticSnapshot(
      focusRegions: [
        FocusRegion(
          identity: identity,
          rect: baseline.bounds,
          focusInteractions: .activate
        )
      ]
    )
    let draw = DrawNode(identity: identity, bounds: .init(origin: .zero, size: .zero))
    let matchingArtifacts = makeStoredArtifacts(
      identity: identity,
      placed: baseline,
      semantics: semantics,
      draw: draw
    )

    retainedState.storeCommittedFrame(
      matchingArtifacts,
      baselinePlacedTree: baseline,
      proposal: .init(width: .finite(10), height: .finite(4))
    )

    let retained = retainedState.input(invalidatedIdentities: [])
    #expect(
      retained.previousPhaseProducts?.proposal == .init(width: .finite(10), height: .finite(4)))
    #expect(retained.previousPhaseProducts?.semantics == semantics)
    #expect(retained.previousPhaseProducts?.draw == draw)
    #expect(
      retained.previousPhaseProducts?.signature
        == RetainedPhaseExtractionSignature.make(from: baseline)
    )
    #expect(
      retained.phaseExtractionProof(
        for: .init(width: .finite(10), height: .finite(4)),
        placed: baseline,
        animationOverlaySnapshot: .init()
      ) == .wholeTreeIdentical
    )
    #expect(
      retained.phaseExtractionProof(
        for: .init(width: .finite(11), height: .finite(4)),
        placed: baseline,
        animationOverlaySnapshot: .init()
      ) == .none
    )
    var changedPlaced = baseline
    changedPlaced.bounds = .init(origin: .zero, size: .init(width: 2, height: 1))
    #expect(
      retained.phaseExtractionProof(
        for: .init(width: .finite(10), height: .finite(4)),
        placed: changedPlaced,
        animationOverlaySnapshot: .init()
      ) == .none
    )
    #expect(
      retained.phaseExtractionProof(
        for: .init(width: .finite(10), height: .finite(4)),
        placed: baseline,
        animationOverlaySnapshot: .init(
          insertionOffsets: [
            .init(identity: identity, dx: 1, dy: 0)
          ]
        )
      ) == .none
    )

    var decorated = baseline
    decorated.bounds = .init(origin: .init(x: 1, y: 0), size: .zero)
    let decoratedArtifacts = makeStoredArtifacts(
      identity: identity,
      placed: decorated,
      semantics: semantics,
      draw: draw
    )

    retainedState.storeCommittedFrame(
      decoratedArtifacts,
      baselinePlacedTree: baseline,
      proposal: .init(width: .finite(10), height: .finite(4))
    )

    #expect(retainedState.input(invalidatedIdentities: []).previousPhaseProducts == nil)
  }

  @Test("retained phase products strip post-commit accessibility announcements")
  func retainedPhaseProductsStripPostCommitAccessibilityAnnouncements() {
    let retainedState = FrameTailRetainedState()
    let identity = testIdentity("Root")
    let baseline = PlacedNode(identity: identity, bounds: .init(origin: .zero, size: .zero))
    let extractionSemantics = SemanticSnapshot(
      focusRegions: [
        FocusRegion(
          identity: identity,
          rect: baseline.bounds,
          focusInteractions: .activate
        )
      ]
    )
    var committedSemantics = extractionSemantics
    committedSemantics.accessibilityAnnouncements = [
      .init(message: "copied", politeness: .polite)
    ]
    let draw = DrawNode(identity: identity, bounds: .init(origin: .zero, size: .zero))
    let artifacts = makeStoredArtifacts(
      identity: identity,
      placed: baseline,
      semantics: committedSemantics,
      draw: draw
    )

    retainedState.storeCommittedFrame(
      artifacts,
      baselinePlacedTree: baseline,
      proposal: .unspecified
    )

    #expect(
      retainedState.input(invalidatedIdentities: []).previousPhaseProducts?.semantics
        == extractionSemantics)
  }

  @Test("an unsafe type-erased draw payload does not starve retained reuse of clean siblings")
  func unsafeTypeErasedPayloadDoesNotStarveCleanSiblingReuse() {
    struct Dots: CanvasDrawing, Equatable {
      func draw(into context: inout CanvasContext) {
        context.setSample(GridSample(x: 0, y: 0))
      }
    }

    let retainedState = FrameTailRetainedState()
    let root = testIdentity("CanvasSibling", "Root")
    let canvasID = testIdentity("CanvasSibling", "Canvas")
    let cleanID = testIdentity("CanvasSibling", "Clean")
    let placed = PlacedNode(
      identity: root,
      bounds: .init(origin: .zero, size: .init(width: 8, height: 2)),
      children: [
        PlacedNode(
          identity: canvasID,
          bounds: .init(origin: .zero, size: .init(width: 8, height: 1)),
          drawPayload: .canvas(.init(drawing: Dots()))
        ),
        PlacedNode(
          identity: cleanID,
          bounds: .init(origin: .init(x: 0, y: 1), size: .init(width: 8, height: 1)),
          drawPayload: .text("clean")
        ),
      ]
    )
    let artifacts = makeStoredArtifacts(
      identity: root,
      placed: placed,
      semantics: .init(),
      draw: DrawExtractor().extract(from: placed)
    )
    retainedState.storeCommittedFrame(
      artifacts,
      baselinePlacedTree: placed,
      proposal: .init(width: .finite(8), height: .finite(2))
    )

    let retained = retainedState.input(invalidatedIdentities: [])
    // The unsupported canvas no longer discards the whole frame's phase products
    // (it previously zeroed them, starving reuse tree-wide); they are retained
    // with a nil whole-tree signature so the per-subtree partial path can run.
    #expect(retained.previousPhaseProducts != nil)
    #expect(retained.previousPhaseProducts?.signature == nil)

    let proof = retained.phaseExtractionProof(
      for: .init(width: .finite(8), height: .finite(2)),
      placed: placed,
      animationOverlaySnapshot: .init()
    )
    // The clean text sibling is reusable; the unsupported canvas never is.
    #expect(proof.canReuseSubtree(rootedAt: cleanID))
    #expect(!proof.canReuseSubtree(rootedAt: canvasID))
  }

  @Test("retained phase proof identifies clean sibling subtrees")
  func retainedPhaseProofIdentifiesCleanSiblingSubtrees() {
    let retainedState = FrameTailRetainedState()
    let root = testIdentity("RetainedPhaseSubtrees", "Root")
    let dirty = testIdentity("RetainedPhaseSubtrees", "Dirty")
    let clean = testIdentity("RetainedPhaseSubtrees", "Clean")
    let previousPlaced = PlacedNode(
      identity: root,
      bounds: .init(origin: .zero, size: .init(width: 8, height: 2)),
      children: [
        PlacedNode(
          identity: dirty,
          bounds: .init(origin: .zero, size: .init(width: 8, height: 1)),
          drawPayload: .text("dirty-1")
        ),
        PlacedNode(
          identity: clean,
          bounds: .init(origin: .init(x: 0, y: 1), size: .init(width: 8, height: 1)),
          drawPayload: .text("clean")
        ),
      ]
    )
    let currentPlaced = PlacedNode(
      identity: root,
      bounds: previousPlaced.bounds,
      children: [
        PlacedNode(
          identity: dirty,
          bounds: previousPlaced.children[0].bounds,
          drawPayload: .text("dirty-2")
        ),
        previousPlaced.children[1],
      ]
    )
    let artifacts = makeStoredArtifacts(
      identity: root,
      placed: previousPlaced,
      semantics: .init(),
      draw: DrawExtractor().extract(from: previousPlaced)
    )
    retainedState.storeCommittedFrame(
      artifacts,
      baselinePlacedTree: previousPlaced,
      proposal: .init(width: .finite(8), height: .finite(2))
    )

    let retained = retainedState.input(invalidatedIdentities: [dirty])
    let proof = retained.phaseExtractionProof(
      for: .init(width: .finite(8), height: .finite(2)),
      placed: currentPlaced,
      animationOverlaySnapshot: .init()
    )

    #expect(proof.canReuseSubtree(rootedAt: clean))
    #expect(!proof.canReuseSubtree(rootedAt: dirty))
  }

  // MARK: - Pre-frame-head offscreen property animation tick

  @Test("pre-frame-head offscreen property tick advances live animation state")
  func preFrameHeadOffscreenPropertyTickAdvancesLiveAnimationState() {
    let controller = AnimationController()
    let animation = Animation.linear(duration: .milliseconds(100))
    controller.register(animation)

    let leafIdentity = testIdentity("PreHeadElision", "Leaf")
    let t0 = MonotonicInstant.now()
    controller.processResolvedTree(
      resolvedLeaf(identity: leafIdentity, opacity: 1.0),
      transaction: .init(),
      timestamp: t0
    )

    var animatingTransaction = TransactionSnapshot()
    animatingTransaction.animationRequest = .animate(animation.animationBox)
    controller.processResolvedTree(
      resolvedLeaf(identity: leafIdentity, opacity: 0.0),
      transaction: animatingTransaction,
      timestamp: t0
    )

    #expect(
      controller.preFrameHeadOffscreenPropertyAnimationRedrawIdentities
        == [leafIdentity]
    )

    let tick = controller.advancePreFrameHeadOffscreenPropertyAnimationTick(
      at: t0.advanced(by: .milliseconds(20))
    )

    #expect(tick.hasPendingWork)
    #expect(tick.nextDeadline != nil)
    #expect(tick.redrawIdentities == [leafIdentity])
    #expect(controller.lastTickResult.hasPendingWork == tick.hasPendingWork)
    #expect(controller.lastTickResult.nextDeadline == tick.nextDeadline)
    #expect(controller.lastTickResult.redrawIdentities == tick.redrawIdentities)
    #expect(controller.activeAnimationCount == 1)
  }

  @Test("pre-frame-head offscreen property tick fires finite animation completion")
  func preFrameHeadOffscreenPropertyTickFiresFiniteCompletion() {
    let controller = AnimationController()
    let animation = Animation.linear(duration: .milliseconds(100))
    controller.register(animation)

    let batchID = AnimationBatchID(90_201)
    let fireCount = FireCounter()
    controller.registerCompletion(batchID: batchID) {
      fireCount.increment()
    }

    let leafIdentity = testIdentity("PreHeadElision", "CompletingLeaf")
    let t0 = MonotonicInstant.now()
    controller.processResolvedTree(
      resolvedLeaf(identity: leafIdentity, opacity: 1.0),
      transaction: .init(),
      timestamp: t0
    )

    var animatingTransaction = TransactionSnapshot()
    animatingTransaction.animationRequest = .animate(animation.animationBox)
    animatingTransaction.animationBatchID = batchID
    controller.processResolvedTree(
      resolvedLeaf(identity: leafIdentity, opacity: 0.0),
      transaction: animatingTransaction,
      timestamp: t0
    )

    let tick = controller.advancePreFrameHeadOffscreenPropertyAnimationTick(
      at: t0.advanced(by: .milliseconds(200))
    )

    #expect(!tick.hasPendingWork)
    #expect(tick.nextDeadline == nil)
    #expect(tick.redrawIdentities == [leafIdentity])
    #expect(fireCount.count == 1)
    #expect(controller.activeAnimationCount == 0)
  }

  @Test("pre-frame-head offscreen property tick prunes completed animation registrations")
  func preFrameHeadOffscreenPropertyTickPrunesLedger() {
    // A finite curve completing during elided off-screen ticks must free its
    // `registeredAnimations` ledger entry exactly as the on-screen tick does
    // (F178): the ledger is append-only outside the prune, so a sequence of
    // distinct finite curves completing off-screen previously grew it without
    // bound for as long as the view stayed elided.
    let controller = AnimationController()
    let leafIdentity = testIdentity("PreHeadElision", "LedgerLeaf")
    var time = MonotonicInstant.now()
    controller.processResolvedTree(
      resolvedLeaf(identity: leafIdentity, opacity: 1.0),
      transaction: .init(),
      timestamp: time
    )
    let baseline = controller.debugStateSnapshot().registeredAnimationCount

    var opacity = 1.0
    for step in 0..<8 {
      // Distinct durations mint distinct animation boxes — each is one
      // ledger entry.
      let animation = Animation.linear(duration: .milliseconds(10 + step))
      controller.register(animation)
      var animatingTransaction = TransactionSnapshot()
      animatingTransaction.animationRequest = .animate(animation.animationBox)
      opacity = opacity == 1.0 ? 0.0 : 1.0
      controller.processResolvedTree(
        resolvedLeaf(identity: leafIdentity, opacity: opacity),
        transaction: animatingTransaction,
        timestamp: time
      )
      // Advance well past the curve's duration so the off-screen tick
      // completes it.
      time = time.advanced(by: .milliseconds(500))
      _ = controller.advancePreFrameHeadOffscreenPropertyAnimationTick(at: time)
      #expect(controller.activeAnimationCount == 0)
    }

    let final = controller.debugStateSnapshot().registeredAnimationCount
    #expect(
      final <= baseline + 1,
      "registeredAnimations grew to \(final) (baseline \(baseline)) across 8 off-screen completions — the off-screen tick is missing the ledger prune"
    )
  }

  // MARK: - commitElided (reduced-commit path)

  /// The correctness-critical invariant for the reduced-commit path:
  /// `FrameHeadTransaction.commitElided()` must fire deferred animation
  /// completions on real-time schedule AND publish the advanced animation
  /// state to the live controller — without any rendering tail or
  /// presentation. This test drives the animation draft to a state with a
  /// deferred completion, then commits the transaction in elided mode and
  /// checks both invariants.
  @Test("commitElided fires the deferred completion and advances live animation state")
  func commitElidedFiresDeferredCompletionAndAdvancesLiveState() throws {
    let liveController = AnimationController()
    let animation = Animation.linear(duration: .milliseconds(100))
    liveController.register(animation)

    // The live controller has not yet observed any tick, so its clock is at
    // the default tick result with no redraw identities.
    #expect(liveController.lastTickResult.redrawIdentities.isEmpty)

    let transaction = makeOneShotFrameHeadTransaction(liveController: liveController)
    let draftController = transaction.animationDraft.controller

    // Register the completion on the DRAFT controller (its frame-head
    // transaction is already active), then drive the property change +
    // tick so the completion is deferred onto the draft rather than fired.
    let batchID = AnimationBatchID(9_101)
    let fireCount = FireCounter()
    draftController.registerCompletion(batchID: batchID) {
      fireCount.increment()
    }

    let leafIdentity = Identity(components: [.named("elided-leaf")])
    var frame1Metadata = DrawMetadata()
    frame1Metadata.baseStyle.explicitOpacity = 1.0
    let frame1 = ResolvedNode(
      identity: leafIdentity,
      kind: .view("Leaf"),
      drawMetadata: frame1Metadata
    )
    let t0 = MonotonicInstant.now()
    draftController.processResolvedTree(frame1, transaction: .init(), timestamp: t0)

    var frame2Metadata = DrawMetadata()
    frame2Metadata.baseStyle.explicitOpacity = 0.0
    var frame2 = ResolvedNode(
      identity: leafIdentity,
      kind: .view("Leaf"),
      drawMetadata: frame2Metadata
    )
    var animatingTransaction = TransactionSnapshot()
    animatingTransaction.animationRequest = .animate(animation.animationBox)
    animatingTransaction.animationBatchID = batchID
    draftController.processResolvedTree(frame2, transaction: animatingTransaction, timestamp: t0)

    // Tick past the animation's nominal duration so the batch completes;
    // because the draft's frame-head transaction is active, the completion
    // is deferred rather than fired immediately.
    // (uses the supplied timestamp, not the wall clock — deterministic by construction)
    let past = t0.advanced(by: .milliseconds(200))
    let draftTick = draftController.applyInterpolations(to: &frame2, at: past)
    #expect(fireCount.count == 0, "completion must be deferred, not fired, before commit")
    #expect(
      !draftTick.redrawIdentities.isEmpty,
      "the draft tick must produce redraw identities so we can prove the live state advanced"
    )

    // Reduced commit: fires deferred completions and publishes advanced
    // animation state to the live controller — no rendering tail.
    _ = transaction.commitElided()

    #expect(fireCount.count == 1, "commitElided must fire the deferred completion exactly once")
    #expect(
      liveController.lastTickResult.redrawIdentities == draftTick.redrawIdentities,
      "commitElided must publish the draft's advanced tick result to the live controller"
    )
  }

  // MARK: - Executor short-circuit

  /// When `commitElidedFrameIfOffscreen` fires right after animation injection, the
  /// synchronous one-shot executor must skip every remaining stage —
  /// late-preference reconciliation, the fused frame tail, and commit — and
  /// return ``RenderExecutionResult/elided``. The tail/commit handlers flip a
  /// flag if they are ever reached; the flag must stay clear.
  @Test("renderOneShot short-circuits the tail and commit when the gate fires")
  func renderOneShotShortCircuitsTailAndCommitWhenGateFires() throws {
    let renderer = DefaultRenderer()
    let draft = renderer.prepareFrameHeadForCancellationTesting(
      Text("offscreen"),
      context: .init(identity: testIdentity("ElidedOneShotRoot")),
      proposal: .init(width: 8, height: 1)
    )
    let reached = StageReachFlags()

    let result = RuntimeRenderPipeline().renderOneShot(
      head: draft,
      handlers: OneShotRenderStageHandlers(
        animationInjection: { $0 },
        commitElidedFrameIfOffscreen: { _ in true },
        latePreferenceReconciliation: { _ in
          reached.latePreference = true
          Issue.record("latePreferenceReconciliation ran for an elided one-shot frame")
          fatalError("unreachable: elided frame must skip late-preference reconciliation")
        },
        fusedFrameTail: { _, _ in
          reached.fusedFrameTail = true
          Issue.record("fusedFrameTail ran for an elided one-shot frame")
          fatalError("unreachable: elided frame must skip the fused frame tail")
        },
        commit: { _, _, _ in
          reached.commit = true
          Issue.record("commit ran for an elided one-shot frame")
          fatalError("unreachable: elided frame must skip commit")
        }
      )
    )

    guard case .elided = result else {
      Issue.record("expected renderOneShot to report .elided")
      return
    }
    #expect(!reached.latePreference)
    #expect(!reached.fusedFrameTail)
    #expect(!reached.commit)

    // Tidy up the prepared head: the synthetic handlers never ran the reduced
    // commit, so discard the still-prepared transaction.
    renderer.abortPreparedFrameHeadForCancellationTesting(draft)
  }

  /// The abortable async executor must short-circuit identically.
  @Test("renderAsync short-circuits the tail and commit when the gate fires")
  func renderAsyncShortCircuitsTailAndCommitWhenGateFires() async throws {
    let renderer = DefaultRenderer()
    let draft = renderer.prepareFrameHeadForCancellationTesting(
      Text("offscreen"),
      context: .init(identity: testIdentity("ElidedAsyncRoot")),
      proposal: .init(width: 8, height: 1)
    )
    let reached = StageReachFlags()

    let result = await RuntimeRenderPipeline().renderAsync(
      head: draft,
      handlers: AsyncRenderStageHandlers<AsyncFrameTailLayoutStageOutput, FrameArtifacts>(
        animationInjection: { $0 },
        commitElidedFrameIfOffscreen: { _ in true },
        latePreferenceReconciliation: { _ in
          reached.latePreference = true
          Issue.record("latePreferenceReconciliation ran for an elided async frame")
          fatalError("unreachable: elided frame must skip late-preference reconciliation")
        },
        fusedFrameTail: { _, _ in
          reached.fusedFrameTail = true
          Issue.record("fusedFrameTail ran for an elided async frame")
          fatalError("unreachable: elided frame must skip the fused frame tail")
        },
        commit: { _, _ in
          reached.commit = true
          Issue.record("commit ran for an elided async frame")
          fatalError("unreachable: elided frame must skip commit")
        }
      )
    )

    guard case .elided = result else {
      Issue.record("expected renderAsync to report .elided")
      return
    }
    #expect(!reached.latePreference)
    #expect(!reached.fusedFrameTail)
    #expect(!reached.commit)

    renderer.abortPreparedFrameHeadForCancellationTesting(draft)
  }

  // MARK: - No-restart trap (run loop)

  /// The load-bearing run-loop invariant: when an off-screen perpetual
  /// animation drives a `[.deadline]`-only frame, the frame is elided (no tail,
  /// no present) but the loop must NOT freeze — the next animation deadline is
  /// still scheduled — AND a subsequent on-screen invalidation (causes include
  /// `.invalidation`, so the gate cannot fire) renders normally.
  @Test("off-screen deadline tick elides but reschedules; on-screen invalidation renders")
  func offscreenDeadlineTickElidesWithoutFreezingThenOnScreenRenders() async throws {
    let terminalSize = CellSize(width: 20, height: 2)
    let rootIdentity = testIdentity("ElisionNoRestartTrap", "Root")
    let terminal = ElisionProbeTerminalHost(surfaceSize: terminalSize)
    let scheduler = FrameScheduler()
    // Freeze the run loop's frame-readiness clock to a single instant captured
    // before any frame is consumed. The off-screen `repeatForever` keeps
    // rescheduling its animation deadline at the REAL future (`> frozenNow`), so
    // pinning the consume instant to `frozenNow` makes those reschedules
    // invisible to the drain: only the test's explicit deadline/invalidation
    // requests drive frames. That is what makes the elision/present counts below
    // deterministic under parallel load. See swift-tui-org/docs/swift-tui/KNOWN-TEST-FLAKES.md.
    let frozenNow = MonotonicInstant.now()
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      terminalInputReader: ElisionEmptyInputReader(),
      signalReader: nil,
      scheduler: scheduler,
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(
        invalidationIdentities: [rootIdentity]
      ),
      environmentValues: {
        var values = EnvironmentValues()
        values.terminalAppearance = terminal.appearance
        values.terminalSize = terminalSize
        return values
      }(),
      proposal: .init(width: terminalSize.width, height: terminalSize.height),
      viewBuilder: { _, _ in
        OffscreenAnimatedProbe()
      }
    )
    runLoop.frameClock = { frozenNow }

    try await withAnimationSinks(runLoop.renderer.internalAnimationController) {

      // Mount the tree (and run the onAppear-triggered follow-up) so the
      // repeatForever animation is in flight and the off-screen border has been
      // committed once (clipped, so it is absent from previousDrawnIdentities).
      //
      // The mount + onAppear-follow-up settle MUST use the SYNCHRONOUS driver. The
      // async driver suspends at `acquireFrameArtifactsAsync` and can drop a
      // committed frame's tail under heavy parallel MainActor contention; if the
      // onAppear-follow-up frame (the one whose resolve registers the
      // `repeatForever` animation) is dropped, `activeAnimationCount` stays 0 and
      // this test flakes. `renderPendingFrames` shares the exact same
      // `applyAcquiredFrame` body but renders straight-line with no suspension and
      // no drop arm, so the registration is deterministic. The elision path under
      // test is still exercised by the ASYNC deadline tick below. See
      // swift-tui-org/docs/swift-tui/KNOWN-TEST-FLAKES.md.
      scheduler.requestInvalidation(of: [rootIdentity])
      var renderedFrames = 0
      try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
      runLoop.renderer.enableSelectiveEvaluation()
      while scheduler.hasPendingFrame(at: frozenNow) {
        try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
      }

      #expect(
        runLoop.renderer.internalAnimationController.activeAnimationCount > 0,
        "the off-screen repeatForever animation must be in flight before the deadline tick"
      )
      let elidedBefore = runLoop.renderer.elidedFrameCount
      let presentsBefore = terminal.presentCount

      // Drive a pure animation-deadline frame: this is the case the gate elides.
      // Consumed at the frozen instant, so ONLY this deadline is ready — the
      // animation's own (real-future) rescheduled deadline stays invisible.
      scheduler.requestDeadline(frozenNow)
      _ = try await runLoop.renderPendingFramesAsync(
        renderedFrames: &renderedFrames,
        eventPump: nil
      )

      // Invariant 1: the deadline-only tick elided (no present), and the gate
      // fired (elided counter advanced).
      #expect(
        runLoop.renderer.elidedFrameCount > elidedBefore,
        "an off-screen deadline-only tick must elide; elidedBefore=\(elidedBefore) after=\(runLoop.renderer.elidedFrameCount)"
      )
      #expect(
        terminal.presentCount == presentsBefore,
        "an elided frame must not present; presentsBefore=\(presentsBefore) after=\(terminal.presentCount)"
      )

      // Invariant 2 (no-restart trap): the loop is not frozen — eliding still
      // scheduled the next animation deadline. Assert a future wake exists rather
      // than probing the real clock at a fixed offset (the original
      // `hasPendingFrame(at: .now() + 100ms)` was the load-flaky part): the
      // rescheduled deadline lands at some real instant `> frozenNow`, so
      // `nextWakeInstant(after:)` returns it regardless of how far real time has
      // drifted under load.
      #expect(
        scheduler.nextWakeInstant(after: frozenNow) != nil,
        "eliding must still reschedule the next animation deadline so the loop keeps ticking"
      )

      // Invariant 3: a subsequent on-screen invalidation renders normally. Its
      // causes include `.invalidation`, so the gate cannot fire (causes != [.deadline]).
      let presentsBeforeInvalidation = terminal.presentCount
      let elidedBeforeInvalidation = runLoop.renderer.elidedFrameCount
      scheduler.requestInvalidation(of: [rootIdentity])
      _ = try await runLoop.renderPendingFramesAsync(
        renderedFrames: &renderedFrames,
        eventPump: nil
      )
      #expect(
        terminal.presentCount > presentsBeforeInvalidation,
        "an on-screen invalidation must render and present a frame"
      )
      #expect(
        runLoop.renderer.elidedFrameCount == elidedBeforeInvalidation,
        "an invalidation-caused frame must not elide"
      )
    }
  }

  // MARK: - Outstanding-proposal guard (hosted resize freeze)

  /// The hosted-resize freeze guard: a deadline-only tick that arrives while
  /// the surface proposal has changed since the last prepared head must
  /// RENDER, not elide. The failing sequence this pins (WebHost drag-resize):
  /// a resize's SIGWINCH frame is cancelled or dropped under a newer intent
  /// (its cause is consumed and never re-pended), and the next wake is an
  /// off-screen animation deadline. Before the guard, that tick's head
  /// consumed the new proposal and `commitElidedFrame` committed the latched
  /// selector state while presenting nothing — every later frame then
  /// compared proposal-equal, took selective evaluation with a clean tree,
  /// and served retained layout at the stale size. The terminal never
  /// resized again.
  ///
  /// Three phases: (A) an unchanged-proposal off-screen tick still elides
  /// (the guard must not disable elision), (B) after a surface resize with
  /// no scheduler cause left behind, the same tick renders and presents,
  /// (C) once the new size has presented, elision resumes.
  @Test("deadline tick renders instead of eliding while a resize is outstanding")
  func outstandingProposalDeadlineTickRendersInsteadOfEliding() async throws {
    let initialSize = CellSize(width: 20, height: 2)
    let rootIdentity = testIdentity("ElisionOutstandingProposal", "Root")
    let terminal = ElisionProbeTerminalHost(surfaceSize: initialSize)
    let scheduler = FrameScheduler()
    // Frozen readiness clock, same rationale as
    // `offscreenDeadlineTickElidesWithoutFreezingThenOnScreenRenders`: the
    // off-screen repeatForever re-arms its deadline at the real future, so
    // pinning the consume instant makes only the test's explicit requests
    // drive frames.
    let frozenNow = MonotonicInstant.now()
    // No `proposal:` override — the run loop must read the LIVE
    // `presentationSurface.surfaceSize`, which is what a hosted transport
    // mutates on resize.
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      terminalInputReader: ElisionEmptyInputReader(),
      signalReader: nil,
      scheduler: scheduler,
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(
        invalidationIdentities: [rootIdentity]
      ),
      environmentValues: {
        var values = EnvironmentValues()
        values.terminalAppearance = terminal.appearance
        values.terminalSize = initialSize
        return values
      }(),
      viewBuilder: { _, _ in
        OffscreenAnimatedProbe()
      }
    )
    runLoop.frameClock = { frozenNow }

    try await withAnimationSinks(runLoop.renderer.internalAnimationController) {
      // Mount synchronously (see the sibling tests: the async driver can drop
      // the onAppear follow-up under parallel load, leaving the repeatForever
      // unregistered).
      scheduler.requestInvalidation(of: [rootIdentity])
      var renderedFrames = 0
      try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
      runLoop.renderer.enableSelectiveEvaluation()
      while scheduler.hasPendingFrame(at: frozenNow) {
        try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
      }
      #expect(
        runLoop.renderer.internalAnimationController.activeAnimationCount > 0,
        "the off-screen repeatForever animation must be in flight"
      )

      // Phase A — unchanged proposal: the off-screen tick still elides.
      let elidedBeforeA = runLoop.renderer.elidedFrameCount
      let presentsBeforeA = terminal.presentCount
      scheduler.requestDeadline(frozenNow)
      _ = try await runLoop.renderPendingFramesAsync(
        renderedFrames: &renderedFrames,
        eventPump: nil
      )
      #expect(
        runLoop.renderer.elidedFrameCount > elidedBeforeA,
        "an off-screen deadline tick at an unchanged proposal must still elide"
      )
      #expect(
        terminal.presentCount == presentsBeforeA,
        "the unchanged-proposal elided tick must not present"
      )

      // Phase B — resize with no scheduler cause left behind (the skipped
      // SIGWINCH shape), then a deadline-only tick: it must render.
      terminal.updateSurfaceSize(CellSize(width: 24, height: 3))
      let elidedBeforeB = runLoop.renderer.elidedFrameCount
      let presentsBeforeB = terminal.presentCount
      scheduler.requestDeadline(frozenNow)
      _ = try await runLoop.renderPendingFramesAsync(
        renderedFrames: &renderedFrames,
        eventPump: nil
      )
      #expect(
        terminal.presentCount > presentsBeforeB,
        """
        a deadline tick with an outstanding resize must render and present; \
        presentsBefore=\(presentsBeforeB) after=\(terminal.presentCount)
        """
      )
      #expect(
        runLoop.renderer.elidedFrameCount == elidedBeforeB,
        """
        a deadline tick with an outstanding resize must not elide; \
        elidedBefore=\(elidedBeforeB) after=\(runLoop.renderer.elidedFrameCount)
        """
      )

      // Phase C — the new size has presented; off-screen elision resumes.
      let elidedBeforeC = runLoop.renderer.elidedFrameCount
      let presentsBeforeC = terminal.presentCount
      scheduler.requestDeadline(frozenNow)
      _ = try await runLoop.renderPendingFramesAsync(
        renderedFrames: &renderedFrames,
        eventPump: nil
      )
      #expect(
        runLoop.renderer.elidedFrameCount > elidedBeforeC,
        "once the resized frame presented, off-screen ticks must elide again"
      )
      #expect(
        terminal.presentCount == presentsBeforeC,
        "the post-resize elided tick must not present"
      )
    }
  }

  // MARK: - End-to-end completion timing (Task 8.1)

  /// The core "coalesce pixels, not logic" invariant, proven END-TO-END through
  /// the real run loop. An OFF-SCREEN finite animation carries a
  /// `withAnimation(...) { ... } completion: { ... }` closure. Its deadline-only
  /// tick frames elide (the animated identity is clipped below a 2-row
  /// ScrollView viewport, so it never reaches `drawnIdentities`), so those
  /// frames render NOTHING and present NOTHING. Yet the completion MUST still
  /// fire on its real-time schedule, because `commitElided()` drains deferred
  /// completions on the live controller exactly like `commit()` does.
  ///
  /// The T5 transaction-layer test proved `commitElided()` fires a deferred
  /// completion at the FrameHeadTransaction boundary; this test proves the same
  /// invariant survives the full executor + run-loop wiring, where the elision
  /// gate is what decides whether the frame's render tail runs at all.
  @Test("off-screen withAnimation completion fires even though its carrier frames elide")
  func offscreenCompletionFiresAcrossElidedFrames() async throws {
    let terminalSize = CellSize(width: 20, height: 2)
    let rootIdentity = testIdentity("ElisionCompletionTiming", "Root")
    let terminal = ElisionProbeTerminalHost(surfaceSize: terminalSize)
    let scheduler = FrameScheduler()
    let completion = FireCounter()
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      terminalInputReader: ElisionEmptyInputReader(),
      signalReader: nil,
      scheduler: scheduler,
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(
        invalidationIdentities: [rootIdentity]
      ),
      environmentValues: {
        var values = EnvironmentValues()
        values.terminalAppearance = terminal.appearance
        values.terminalSize = terminalSize
        return values
      }(),
      proposal: .init(width: terminalSize.width, height: terminalSize.height),
      viewBuilder: { _, _ in
        OffscreenCompletingProbe(completion: completion)
      }
    )
    // Spend the probe's 80 ms animation schedule in VIRTUAL time. On the real
    // clock the mount frame alone costs more than 80 ms on an ordinary machine
    // (measured: ~126 ms for this 50-row probe), so the finite animation had
    // already completed before the first assertion — `activeAnimationCount`
    // back to 0, `completion.count` already 1, and the tick loop below never
    // entered, leaving `elidedFrameCount` at 0. That is not a race a rerun can
    // win: setup cost is a fixed overrun of a fixed budget, which is why the
    // amd64 lane was deterministically red. With the frame clock virtual, setup
    // costs zero animation time and every tick advances exactly one step.
    let clock = VirtualFrameClock(MonotonicInstant.now())
    runLoop.frameClock = { [clock] in clock.now }

    try await withAnimationSinks(runLoop.renderer.internalAnimationController) {

      // Mount + run the onAppear follow-up so the finite off-screen animation is
      // in flight and the clipped border has committed once (absent from
      // previousDrawnIdentities).
      scheduler.requestInvalidation(of: [rootIdentity])
      var renderedFrames = 0
      // Synchronous setup: the async driver suspends at `acquireFrameArtifactsAsync`
      // and can drop the onAppear-follow-up frame's tail under heavy parallel
      // MainActor contention, leaving the animation unregistered
      // (activeAnimationCount == 0) and flaking this test. `renderPendingFrames`
      // shares the exact same `applyAcquiredFrame` body but renders straight-line
      // with no suspension and no drop arm, so registration is deterministic; the
      // elision path under test is still driven via the ASYNC ticks below. See
      // swift-tui-org/docs/swift-tui/KNOWN-TEST-FLAKES.md.
      try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
      runLoop.renderer.enableSelectiveEvaluation()
      // Probed at the virtual instant, so the animation's own rescheduled
      // deadline (armed one cadence into the virtual future) stays invisible to
      // the settle loop and only the mount follow-up frames run.
      while scheduler.hasPendingFrame(at: clock.now) {
        try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
      }

      #expect(
        runLoop.renderer.internalAnimationController.activeAnimationCount > 0,
        "the off-screen finite animation must be in flight before its completion drains"
      )
      #expect(
        completion.count == 0,
        "the finite animation must not have completed during the mount frames"
      )

      let elidedBefore = runLoop.renderer.elidedFrameCount
      let presentsBefore = terminal.presentCount

      // Drive deadline-only tick frames until the finite animation's schedule
      // elapses and the completion fires. Each tick advances the virtual frame
      // clock by one 16 ms step and requests its deadline at the new instant,
      // so `deriveFrameInstant` stamps the frame with exactly that instant and
      // the 80 ms curve completes on step 5 — the same step on every machine.
      // The carrier tick is off-screen-only, so it elides instead of presenting.
      //
      // The cap is now a wedge backstop rather than the termination condition:
      // in virtual time ticks convert to duration exactly, so it can be a tight
      // multiple of the steps the animation actually needs. It replaces the old
      // wall-clock bound, which measured the machine rather than the animation.
      var ticks = 0
      let maxTicks = 32
      while completion.count == 0 && ticks < maxTicks {
        scheduler.requestDeadline(clock.advance(by: .milliseconds(16)))
        _ = try await runLoop.renderPendingFramesAsync(
          renderedFrames: &renderedFrames,
          eventPump: nil
        )
        ticks += 1
      }

      // INVARIANT A: the completion fired even though no carrier frame presented.
      #expect(
        completion.count == 1,
        "the off-screen withAnimation completion must fire on real-time schedule; ticks=\(ticks)"
      )
      // INVARIANT B: at least one deadline-only carrier frame actually elided —
      // proving the completion rode through the reduced-commit path, not a render.
      #expect(
        runLoop.renderer.elidedFrameCount > elidedBefore,
        """
        at least one deadline-only tick carrying the completion must have elided; \
        elidedBefore=\(elidedBefore) after=\(runLoop.renderer.elidedFrameCount)
        """
      )
      // INVARIANT C: no off-screen carrier tick presented a frame.
      #expect(
        terminal.presentCount == presentsBefore,
        """
        off-screen deadline ticks (including the one that fired the completion) \
        must not present; presentsBefore=\(presentsBefore) after=\(terminal.presentCount)
        """
      )
    }
  }

  // MARK: - Oracle soundness (Task 8.2)

  /// Guards the disjointness branch of the elision gate: a deadline-only tick
  /// whose redraw set OVERLAPS the visible `drawnIdentities` must NOT be
  /// elided — it renders and presents.
  ///
  /// Soundness rationale (corrected). The load-bearing safety guarantee for
  /// elision is NOT `redrawIdentities`. `applyInterpolations` populates
  /// `redrawIdentities` with ONLY the directly-animated identity (every scope)
  /// plus removal identities — it NEVER records layout-affected siblings. The
  /// layout-affecting animatable slots (`frameWidth`/`frameHeight`/`offset`/
  /// `position`/`padding`; see `AnimationModels.AnimatableSlot`) animate through
  /// this same `.property` path: they mutate `node.layoutBehavior` in place
  /// WITHOUT dirtying siblings, WITHOUT adding `.invalidation`, and WITHOUT
  /// adding any sibling to `redrawIdentities`. So `redrawIdentities` cannot, by
  /// construction, observe a sibling that an off-screen size animation might
  /// shift.
  ///
  /// The REAL safety guarantee is `drawnIdentities`: it is a geometric
  /// PAINT-VISIBILITY predicate computed in `Rasterizer+Paint.swift` — a node
  /// fully clipped out of the viewport is NEVER recorded; only nodes whose
  /// painted bounds intersect the viewport (width > 0 && height > 0 after clip)
  /// are inserted. An off-screen animated identity is therefore absent from
  /// `drawnIdentities` → disjoint → safely elidable. If an off-screen size
  /// animation ever grew the child enough to push it into the viewport, the
  /// child's painted bounds would intersect the viewport → it WOULD land in
  /// `drawnIdentities` → disjointness breaks → elision is correctly
  /// disqualified. The load-bearing invariant is thus: "clipped-out identities
  /// must NEVER be recorded in `drawnIdentities`" (documented at the recording
  /// site in `Sources/SwiftTUICore/Raster/Rasterizer+Paint.swift`).
  ///
  /// This means a purely off-screen animation cannot be constructed to force a
  /// VISIBLE sibling into the tick's `redrawIdentities` — not because clipping
  /// "isolates redraw" (it does not touch the redraw set at all), but because
  /// `redrawIdentities` simply never tracks siblings. So this test takes the
  /// form that DOES exercise the gate's disjointness branch in the
  /// failing-to-elide direction: an ON-SCREEN animation whose tick redraw set
  /// overlaps `drawnIdentities` must NOT elide. If the gate ever wrongly
  /// reported disjointness for a visible animation, this frame would silently
  /// stop presenting. The complementary off-screen LAYOUT-animation case (a
  /// clipped size animation still elides because the child stays out of
  /// `drawnIdentities`) is covered by
  /// ``offscreenLayoutAnimationStillElides()``.
  @Test("on-screen deadline tick whose redraw overlaps drawnIdentities is NOT elided")
  func onScreenOverlappingDeadlineTickRenders() async throws {
    let terminalSize = CellSize(width: 20, height: 20)
    let rootIdentity = testIdentity("ElisionOracleSoundness", "Root")
    let terminal = ElisionProbeTerminalHost(surfaceSize: terminalSize)
    let scheduler = FrameScheduler()
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      terminalInputReader: ElisionEmptyInputReader(),
      signalReader: nil,
      scheduler: scheduler,
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(
        invalidationIdentities: [rootIdentity]
      ),
      environmentValues: {
        var values = EnvironmentValues()
        values.terminalAppearance = terminal.appearance
        values.terminalSize = terminalSize
        return values
      }(),
      proposal: .init(width: terminalSize.width, height: terminalSize.height),
      viewBuilder: { _, _ in
        OnScreenAnimatedProbe()
      }
    )
    // Same virtual-clock discipline as the off-screen tests. This one is green
    // today only because its probe is a single on-screen row (a cheap frame),
    // but its settle loop probes `hasPendingFrame` against a live
    // `repeatForever` re-arm — the identical livelock shape that took down
    // `removalTransitionInterleavedWithElisionDrains` on the amd64 lane. Held
    // still, the re-arm cannot be due at the re-check.
    let clock = VirtualFrameClock(MonotonicInstant.now())
    runLoop.frameClock = { [clock] in clock.now }

    try await withAnimationSinks(runLoop.renderer.internalAnimationController) {

      scheduler.requestInvalidation(of: [rootIdentity])
      var renderedFrames = 0
      // Synchronous setup: the async driver suspends at `acquireFrameArtifactsAsync`
      // and can drop the onAppear-follow-up frame's tail under heavy parallel
      // MainActor contention, leaving the animation unregistered
      // (activeAnimationCount == 0) and flaking this test. `renderPendingFrames`
      // shares the exact same `applyAcquiredFrame` body but renders straight-line
      // with no suspension and no drop arm, so registration is deterministic; the
      // elision path under test is still driven via the ASYNC ticks below. See
      // swift-tui-org/docs/swift-tui/KNOWN-TEST-FLAKES.md.
      try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
      runLoop.renderer.enableSelectiveEvaluation()
      while scheduler.hasPendingFrame(at: clock.now) {
        try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
      }

      #expect(
        runLoop.renderer.internalAnimationController.activeAnimationCount > 0,
        "the on-screen repeatForever animation must be in flight before the deadline tick"
      )

      let elidedBefore = runLoop.renderer.elidedFrameCount
      let presentsBefore = terminal.presentCount

      // Drive a pure animation-deadline frame. The animated border is INSIDE the
      // viewport, so the tick's redrawIdentities overlap drawnIdentities; the gate
      // must therefore NOT fire. One virtual step, so the tick lands on an
      // instant the animation has genuinely advanced to.
      scheduler.requestDeadline(clock.advance(by: .milliseconds(16)))
      _ = try await runLoop.renderPendingFramesAsync(
        renderedFrames: &renderedFrames,
        eventPump: nil
      )

      #expect(
        runLoop.renderer.elidedFrameCount == elidedBefore,
        """
        a visible deadline-only tick whose redraw overlaps drawnIdentities must \
        NOT elide; elidedBefore=\(elidedBefore) after=\(runLoop.renderer.elidedFrameCount)
        """
      )
      #expect(
        terminal.presentCount > presentsBefore,
        """
        a visible deadline-only tick must render and present a frame; \
        presentsBefore=\(presentsBefore) after=\(terminal.presentCount)
        """
      )
    }
  }

  // MARK: - Off-screen LAYOUT animation soundness

  /// The genuinely interesting elision boundary: a LAYOUT-affecting off-screen
  /// animation. Every other probe in this suite animates the paint-only
  /// `borderBlendPhase`; this one animates `frameHeight` (a member of
  /// `AnimatableSlot`'s layout-affecting set) so the in-flight tick mutates
  /// `node.layoutBehavior` rather than a paint attribute.
  ///
  /// This directly exercises the corrected soundness argument (see
  /// ``onScreenOverlappingDeadlineTickRenders()``): `applyInterpolations`
  /// routes a `frameHeight` animation through the same `.property` path that
  /// only inserts the directly-animated identity into `redrawIdentities` — it
  /// never dirties siblings and never adds `.invalidation`. The frame's safety
  /// therefore rests entirely on `drawnIdentities`: the animated view is
  /// clipped far below a 2-row ScrollView viewport, so its painted bounds never
  /// intersect the viewport and it is never recorded in `drawnIdentities`.
  ///
  /// Asserts that a `[.deadline]`-only tick for this off-screen LAYOUT
  /// animation (1) keeps the clipped child OUT of `drawnIdentities`, and (2) is
  /// elided (`elidedFrameCount` advances, `presentCount` stays flat) — proving
  /// a clipped LAYOUT animation is safely elided, not merely a clipped paint
  /// animation.
  ///
  /// The argument below is scoped to `.property` animations. Work owned by the
  /// placed-overlay pass — an insertion offset, a matched-geometry travel, or
  /// an exit overlay — breaks its premise: it relocates the node itself across
  /// the viewport boundary, from or to a position that `drawnIdentities` never
  /// recorded. Those disqualify elision outright rather than relying on that
  /// set. See ``offsetOnlyInsertionTransitionIsNeverElided()`` and
  /// ``offsetOnlyRemovalTransitionDrainsOffScreen()``.
  ///
  /// Sibling-near-viewport-edge variant NOT added — and it is unconstructible
  /// in this layout/clip model, not merely skipped. A `frameHeight` animation
  /// only ever mutates its OWN node's `layoutBehavior` and only inserts its OWN
  /// identity into `redrawIdentities`; it does not push or resize any sibling.
  /// The only path by which an off-screen size animation could affect visible
  /// output is by growing its OWN painted bounds back into the viewport — in
  /// which case THAT identity (not a sibling) enters `drawnIdentities`,
  /// disjointness breaks, and elision is correctly disqualified. There is no
  /// construction in which an off-screen animation moves a DISTINCT visible
  /// sibling, because the framework never propagates an animated size delta to
  /// a sibling's `redrawIdentities` or to its painted geometry through this
  /// animation path. The "self grows into viewport → not disjoint → not elided"
  /// case is already the contrapositive guarded by
  /// ``onScreenOverlappingDeadlineTickRenders()`` (a visible animated identity
  /// is in `drawnIdentities`, so it does not elide).
  @Test("off-screen frameHeight (layout) animation still elides on a deadline-only tick")
  func offscreenLayoutAnimationStillElides() async throws {
    let terminalSize = CellSize(width: 20, height: 2)
    let rootIdentity = testIdentity("ElisionOffscreenLayoutAnim", "Root")
    let terminal = ElisionProbeTerminalHost(surfaceSize: terminalSize)
    let scheduler = FrameScheduler()
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      terminalInputReader: ElisionEmptyInputReader(),
      signalReader: nil,
      scheduler: scheduler,
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(
        invalidationIdentities: [rootIdentity]
      ),
      environmentValues: {
        var values = EnvironmentValues()
        values.terminalAppearance = terminal.appearance
        values.terminalSize = terminalSize
        return values
      }(),
      proposal: .init(width: terminalSize.width, height: terminalSize.height),
      viewBuilder: { _, _ in
        OffscreenLayoutAnimatedProbe()
      }
    )
    // Same virtual-clock discipline as the off-screen tests: this probe carries
    // the same 50-row filler as the two that failed on amd64, so its settle
    // loop has the same live-`repeatForever` livelock exposure. Green today,
    // latent tomorrow.
    let clock = VirtualFrameClock(MonotonicInstant.now())
    runLoop.frameClock = { [clock] in clock.now }

    try await withAnimationSinks(runLoop.renderer.internalAnimationController) {

      // Mount + run the onAppear-triggered follow-up so the frameHeight animation
      // is in flight and the clipped subtree has committed once (absent from
      // previousDrawnIdentities because it is below the 2-row viewport).
      scheduler.requestInvalidation(of: [rootIdentity])
      var renderedFrames = 0
      // Synchronous setup: the async driver suspends at `acquireFrameArtifactsAsync`
      // and can drop the onAppear-follow-up frame's tail under heavy parallel
      // MainActor contention, leaving the animation unregistered
      // (activeAnimationCount == 0) and flaking this test. `renderPendingFrames`
      // shares the exact same `applyAcquiredFrame` body but renders straight-line
      // with no suspension and no drop arm, so registration is deterministic; the
      // elision path under test is still driven via the ASYNC ticks below. See
      // swift-tui-org/docs/swift-tui/KNOWN-TEST-FLAKES.md.
      try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
      runLoop.renderer.enableSelectiveEvaluation()
      while scheduler.hasPendingFrame(at: clock.now) {
        try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
      }

      let controller = runLoop.renderer.internalAnimationController
      #expect(
        controller.activeAnimationCount > 0,
        "the off-screen frameHeight animation must be in flight before the deadline tick"
      )

      // Self-check: the in-flight animation must genuinely be a LAYOUT animation
      // (the `.frameHeight` property slot), not a vacuous paint or no-op
      // animation. If this ever regresses to a non-layout scope the test would
      // silently stop covering the interesting boundary.
      let activeScopes = controller.debugStateSnapshot().activeAnimationKeys.map(\.scope)
      #expect(
        activeScopes.contains(.property(.frameHeight)),
        "the active animation must be the frameHeight layout slot; scopes=\(activeScopes)"
      )

      let elidedBefore = runLoop.renderer.elidedFrameCount
      let presentsBefore = terminal.presentCount

      // Drive a pure animation-deadline frame for the off-screen LAYOUT
      // animation: this is the case the gate must elide. One virtual step, so
      // the frameHeight curve has genuinely advanced when the tick lands.
      scheduler.requestDeadline(clock.advance(by: .milliseconds(16)))
      _ = try await runLoop.renderPendingFramesAsync(
        renderedFrames: &renderedFrames,
        eventPump: nil
      )

      // ASSERTION 1 — the clipped layout-animated identity stays OUT of
      // drawnIdentities. The deadline tick just ran, so the controller's
      // lastTickResult names the frameHeight-animated identity in its
      // redrawIdentities. That set must be non-empty (the layout animation IS
      // ticking) and DISJOINT from the committed drawnIdentities — i.e. the
      // animated child, clipped below the 2-row viewport, was never recorded as
      // painted. This is the paint-visibility predicate elision soundness rests
      // on, exercised by a LAYOUT animation rather than the paint-only blend
      // phase.
      let redraw = controller.lastTickResult.redrawIdentities
      let drawn = runLoop.renderer.frameTailRenderer.previousDrawnIdentities
      #expect(
        !redraw.isEmpty,
        "the off-screen frameHeight tick must name its animated identity in redrawIdentities"
      )
      #expect(
        redraw.isDisjoint(with: drawn),
        """
        a layout-animated identity clipped below the viewport must NOT be recorded \
        in drawnIdentities; redraw=\(redraw) drawn∩redraw=\(redraw.intersection(drawn))
        """
      )

      // ASSERTION 2 — the off-screen LAYOUT deadline tick elided (gate fired) and
      // presented nothing.
      #expect(
        runLoop.renderer.elidedFrameCount > elidedBefore,
        """
        an off-screen LAYOUT (frameHeight) deadline-only tick must elide; \
        elidedBefore=\(elidedBefore) after=\(runLoop.renderer.elidedFrameCount)
        """
      )
      #expect(
        terminal.presentCount == presentsBefore,
        """
        an elided off-screen LAYOUT tick must not present; \
        presentsBefore=\(presentsBefore) after=\(terminal.presentCount)
        """
      )
    }
  }

  // MARK: - Removal transition interleaved with elision (Task 8.3)

  /// Correctness guard for skipping `capturePlacedTree` on elided frames: a
  /// removal transition is in flight WHILE off-screen deadline ticks are being
  /// elided, then the loop runs to quiescence. Eliding off-screen frames must
  /// not corrupt removal bookkeeping — the removal overlay must drain and the
  /// loop must reach a quiescent (no-pending-work) state without crashing.
  ///
  /// The probe interleaves two animation populations: a perpetual off-screen
  /// `repeatForever` border (the elision source, clipped below the viewport)
  /// and a finite on-screen removal transition triggered from onAppear. The
  /// off-screen border keeps producing deadline-only ticks that elide; the
  /// removal must still complete correctly through them.
  @Test("removal transition interleaved with off-screen elision drains correctly")
  func removalTransitionInterleavedWithElisionDrains() async throws {
    let terminalSize = CellSize(width: 20, height: 2)
    let rootIdentity = testIdentity("ElisionRemovalInterleave", "Root")
    let terminal = ElisionProbeTerminalHost(surfaceSize: terminalSize)
    let scheduler = FrameScheduler()
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      terminalInputReader: ElisionEmptyInputReader(),
      signalReader: nil,
      scheduler: scheduler,
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(
        invalidationIdentities: [rootIdentity]
      ),
      environmentValues: {
        var values = EnvironmentValues()
        values.terminalAppearance = terminal.appearance
        values.terminalSize = terminalSize
        return values
      }(),
      proposal: .init(width: terminalSize.width, height: terminalSize.height),
      viewBuilder: { _, _ in
        InterleavedRemovalProbe()
      }
    )
    // Virtual frame clock, for two reasons this test needs at once. (1) The
    // removal's 80 ms schedule must be spent by ticks, not by setup cost — see
    // `offscreenCompletionFiresAcrossElidedFrames`. (2) The settle loop between
    // the phases probes readiness with `hasPendingFrame`, and once the
    // off-screen border's `repeatForever` is live it re-arms a deadline one
    // 33 ms cadence out on every frame. On the real clock, any machine whose
    // per-frame cost reaches that cadence finds the re-arm already due at the
    // re-check and the loop never exits — the slow-machine livelock
    // `drainPassReturnsWhenFrameCostExceedsAnimationCadence` documents. It
    // spun until the shared tick cap was exhausted, which starved Phase 2 of
    // its budget and left `elidedFrameCount` at 0 on the amd64 lane. Held
    // still, the re-arm lands in the virtual future and stays invisible.
    let clock = VirtualFrameClock(MonotonicInstant.now())
    runLoop.frameClock = { [clock] in clock.now }

    try await withAnimationSinks(runLoop.renderer.internalAnimationController) {

      // Mount + the onAppear-triggered follow-up frames: the panel's removal
      // transition starts. The two animation populations are registered on
      // SEPARATE frames (the panel's removal on the follow-up, the border's
      // `repeatForever` on the frame after it flips `showPanel`), so they never
      // share an animation transaction — that separation, not their ordering,
      // is what keeps the removal's box unambiguous. By the time this drain
      // returns BOTH are live: `removingIdentities` holds the departing panel
      // and `activeAnimationKeys` holds the border's `borderBlendPhase`.
      //
      // This setup MUST use the SYNCHRONOUS driver. The async driver suspends at
      // `acquireFrameArtifactsAsync` and can drop a committed frame's tail under
      // heavy parallel MainActor contention; if the onAppear-follow-up frame (the
      // one whose resolve starts the removal transition) is dropped, the removal
      // never registers and `removingIdentities` is empty here. `renderPendingFrames`
      // shares the exact same `applyAcquiredFrame` body but renders straight-line
      // with no suspension and no drop arm, so the removal start is deterministic.
      // The elision path under test is still exercised by the ASYNC deadline ticks
      // in Phase 1/2 below. See swift-tui-org/docs/swift-tui/KNOWN-TEST-FLAKES.md.
      scheduler.requestInvalidation(of: [rootIdentity])
      var renderedFrames = 0
      try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
      let controller = runLoop.renderer.internalAnimationController
      runLoop.renderer.enableSelectiveEvaluation()

      #expect(
        !controller.debugStateSnapshot().removingIdentities.isEmpty,
        "the on-screen removal transition must be in flight before the interleaving"
      )

      // Phase 1: drive deadline ticks until the removal transition has fully
      // drained (its overlay purged). While the removal is in flight its identity
      // is on-screen and in the tick's redrawIdentities, so those frames render
      // and present — they do NOT elide. One 16 ms virtual step per tick, so the
      // 80 ms removal drains on step 5 on every machine.
      //
      // Each phase carries its OWN budget. The single shared counter this
      // replaced meant an overrun in any earlier loop silently consumed the
      // budget of every later one, so Phase 2 reported "nothing elided" when
      // the real fault was upstream. Per-phase caps make each failure name its
      // own phase.
      let maxTicks = 32
      var removalTicks = 0
      while !controller.debugStateSnapshot().removingIdentities.isEmpty
        && removalTicks < maxTicks
      {
        scheduler.requestDeadline(clock.advance(by: .milliseconds(16)))
        _ = try await runLoop.renderPendingFramesAsync(
          renderedFrames: &renderedFrames,
          eventPump: nil
        )
        removalTicks += 1
      }

      // The removal must have drained — no crash, overlay purged.
      #expect(
        controller.debugStateSnapshot().removingIdentities.isEmpty,
        "the removal overlay must drain to completion; removalTicks=\(removalTicks)"
      )

      // Settle any frames the removal's final tick left pending, so the graph is
      // quiescent before Phase 2 measures elision. Synchronous driver again: the
      // async path could drop a follow-up frame's tail under contention. The
      // elided ticks under test are driven via the ASYNC path in Phase 2 below.
      // The clock is held still across this settle loop: the border's
      // `repeatForever` re-arm lands one cadence into the virtual future, so
      // readiness drains to false instead of livelocking (see the clock's note
      // at the top of this test).
      var settleFrames = 0
      while scheduler.hasPendingFrame(at: clock.now) && settleFrames < maxTicks {
        try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
        settleFrames += 1
      }
      #expect(
        settleFrames < maxTicks,
        "the post-removal settle must reach quiescence; settleFrames=\(settleFrames)"
      )
      #expect(
        controller.activeAnimationCount > 0,
        "the off-screen repeatForever border must be in flight after the removal drains"
      )

      // Phase 2: now that the removal has drained on the surviving graph, the
      // off-screen border's deadline ticks must elide — proving the reduced-commit
      // path (capturePlacedTree skipped) left the post-removal placed-tree
      // bookkeeping intact.
      let elidedBefore = runLoop.renderer.elidedFrameCount
      var elisionTicks = 0
      while runLoop.renderer.elidedFrameCount == elidedBefore && elisionTicks < maxTicks {
        scheduler.requestDeadline(clock.advance(by: .milliseconds(16)))
        _ = try await runLoop.renderPendingFramesAsync(
          renderedFrames: &renderedFrames,
          eventPump: nil
        )
        elisionTicks += 1
      }
      #expect(
        runLoop.renderer.elidedFrameCount > elidedBefore,
        """
        off-screen ticks must elide on the post-removal graph; \
        elidedBefore=\(elidedBefore) after=\(runLoop.renderer.elidedFrameCount) \
        elisionTicks=\(elisionTicks)
        """
      )

      // The loop must remain healthy: a final on-screen invalidation renders
      // correctly, confirming the committed graph survived the interleaving. Its
      // causes include `.invalidation`, so it cannot elide.
      let presentsBeforeFinal = terminal.presentCount
      scheduler.requestInvalidation(of: [rootIdentity])
      _ = try await runLoop.renderPendingFramesAsync(
        renderedFrames: &renderedFrames,
        eventPump: nil
      )
      #expect(
        terminal.presentCount > presentsBeforeFinal,
        "a post-removal on-screen invalidation must still render and present"
      )
    }
  }

  // MARK: - Slow-machine drain termination (F41 reland guard)

  /// The red-pin livelock guard (report 2026-07-07-008): on a machine whose
  /// per-frame cost meets or exceeds the 33 ms animation cadence, every
  /// deadline a live `repeatForever` animation re-arms during a drain is
  /// already due by the loop's re-check. With the scheduler's surviving
  /// deadline set (F41) and no drain-pass cut, one `renderPendingFramesAsync`
  /// call never returns — the hang that killed the Linux push gate at pin
  /// `9f2a8bfd` (this suite's interleave test was the deterministic victim on
  /// GitHub's 4-core runners). The frame drivers now bound each drain pass to
  /// the deadlines armed before pass entry, so this call must return on ANY
  /// machine.
  ///
  /// Machine speed is simulated, not assumed: the injectable
  /// `frameClock` advances 40 ms per read — past the animation
  /// cadence — so every in-pass re-arm is already due at the next consume,
  /// exactly the CI-class runner shape, however fast the real host is.
  @Test(
    "a drain pass returns on a machine slower than the animation cadence",
    .timeLimit(.minutes(1))
  )
  func drainPassReturnsWhenFrameCostExceedsAnimationCadence() async throws {
    let terminalSize = CellSize(width: 20, height: 2)
    let rootIdentity = testIdentity("SlowMachineDrain", "Root")
    let terminal = ElisionProbeTerminalHost(surfaceSize: terminalSize)
    let scheduler = FrameScheduler()
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      terminalInputReader: ElisionEmptyInputReader(),
      signalReader: nil,
      scheduler: scheduler,
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(
        invalidationIdentities: [rootIdentity]
      ),
      environmentValues: {
        var values = EnvironmentValues()
        values.terminalAppearance = terminal.appearance
        values.terminalSize = terminalSize
        return values
      }(),
      proposal: .init(width: terminalSize.width, height: terminalSize.height),
      viewBuilder: { _, _ in
        OffscreenAnimatedProbe()
      }
    )

    try await withAnimationSinks(runLoop.renderer.internalAnimationController) {

      // Mount + settle the onAppear follow-up (synchronous driver — same
      // rationale as the tests above; see swift-tui-org/docs/swift-tui/KNOWN-TEST-FLAKES.md).
      //
      // The settle probe is pinned to an instant captured before mount so the
      // repeatForever's re-arm can never be due at the re-check. Probed against
      // the real clock it was the same livelock this test exists to guard
      // against, one loop earlier: on a machine at or past the 33 ms cadence
      // the settle spins to its own cap, and 400 emulated frames overrun the
      // one-minute limit before the drain pass under test even starts.
      // Invalidation causes are instant-independent, so the onAppear follow-up
      // still runs — only deadline readiness is held out.
      let settleNow = MonotonicInstant.now()
      scheduler.requestInvalidation(of: [rootIdentity])
      var renderedFrames = 0
      try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
      runLoop.renderer.enableSelectiveEvaluation()
      var settleFrames = 0
      while scheduler.hasPendingFrame(at: settleNow) && settleFrames < 400 {
        try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
        settleFrames += 1
      }
      #expect(
        runLoop.renderer.internalAnimationController.activeAnimationCount > 0,
        "the repeatForever animation must be in flight before the slow drain"
      )

      // The seed deadline is armed AT the clock's start instant so the pass's
      // first consume (which reads exactly `drainStart`) sees it due — armed
      // any later it would sit in the first read's future and the drain would
      // return vacuously, never establishing the re-arm chain under test.
      let drainStart = MonotonicInstant.now()
      let clock = SteppingReadinessClock(start: drainStart, step: .milliseconds(40))
      runLoop.frameClock = { [clock] in clock.nextReading() }

      // One drain pass on the simulated slow machine. RETURNING is the
      // regression assertion: without the drain-pass deadline cut this awaits
      // forever (caught here by the time limit rather than a CI step watchdog).
      scheduler.requestDeadline(drainStart)
      let framesBeforeDrain = renderedFrames
      _ = try await runLoop.renderPendingFramesAsync(
        renderedFrames: &renderedFrames,
        eventPump: nil
      )
      #expect(
        renderedFrames > framesBeforeDrain,
        "the seed deadline must have driven at least one frame (elided or committed)"
      )

      // The cut withholds in-pass re-arms; it must not LOSE them — the
      // animation pump stays alive for the next pass.
      #expect(
        scheduler.hasPendingFrame(at: .now().advanced(by: .seconds(60))),
        "the in-pass animation re-arm must stay pending for the next drain pass"
      )
    }
  }

  // MARK: - Placed-level geometry animations

  /// An offset-only insertion transition (`.slide`, `.move(edge:)`,
  /// `.offset(x:y:)`) is the construction the `drawnIdentities` proxy cannot
  /// express: the arriving view starts OUTSIDE the slot it is about to occupy,
  /// so it has never been painted, so every deadline tick reads as "this redraw
  /// cannot reach the surface". Eliding it skips the placed-overlay pass — the
  /// sole owner of that animation's evaluation, advance, and completion — which
  /// freezes the offset at its starting sample, which keeps the identity
  /// off-surface, which keeps the next tick elidable. The view then never
  /// appears at all: in the gallery's Transitions section the slide-in was
  /// invisible until an unrelated click forced a real frame, and a late click
  /// popped it straight to its final position.
  ///
  /// Guards the fix at the level that actually failed: frames must keep
  /// rendering (nothing elides while the offset is live) and the text must be
  /// on the presented raster by the time the curve ends, with no input at all.
  @Test("an offset-only insertion transition is never elided and lands on screen")
  func offsetOnlyInsertionTransitionIsNeverElided() async throws {
    let terminalSize = CellSize(width: 20, height: 3)
    let rootIdentity = testIdentity("ElisionSlideInsertion", "Root")
    let terminal = ElisionProbeTerminalHost(surfaceSize: terminalSize)
    let scheduler = FrameScheduler()
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      terminalInputReader: ElisionEmptyInputReader(),
      signalReader: nil,
      scheduler: scheduler,
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(
        invalidationIdentities: [rootIdentity]
      ),
      environmentValues: {
        var values = EnvironmentValues()
        values.terminalAppearance = terminal.appearance
        values.terminalSize = terminalSize
        return values
      }(),
      proposal: .init(width: terminalSize.width, height: terminalSize.height),
      viewBuilder: { _, _ in
        SlideInsertionProbe()
      }
    )
    // Virtual clock: the 300 ms curve is spent by ticks, not by setup cost.
    let clock = VirtualFrameClock(MonotonicInstant.now())
    runLoop.frameClock = { [clock] in clock.now }

    try await withAnimationSinks(runLoop.renderer.internalAnimationController) {
      // Synchronous mount + onAppear follow-up, for the determinism reasons the
      // sibling tests document.
      scheduler.requestInvalidation(of: [rootIdentity])
      var renderedFrames = 0
      try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
      runLoop.renderer.enableSelectiveEvaluation()
      while scheduler.hasPendingFrame(at: clock.now) {
        try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
      }

      let controller = runLoop.renderer.internalAnimationController
      #expect(
        controller.activeInsertionOffsetCount > 0,
        "the insertion offset animation must be in flight before the ticks"
      )
      #expect(
        controller.hasPlacedPassOwnedAnimationWork,
        "an insertion offset is placed-pass-owned work"
      )
      #expect(
        !Self.surfaceContains("slide", terminal),
        "the arriving view starts outside its own slot, so it is not on screen yet"
      )

      let elidedBefore = runLoop.renderer.elidedFrameCount

      // Deadline-only ticks, no input of any kind — exactly the situation the
      // user is in while watching the animation.
      var ticks = 0
      while controller.activeInsertionOffsetCount > 0 && ticks < 40 {
        scheduler.requestDeadline(clock.advance(by: .milliseconds(16)))
        _ = try await runLoop.renderPendingFramesAsync(
          renderedFrames: &renderedFrames,
          eventPump: nil
        )
        ticks += 1
      }

      #expect(
        controller.activeInsertionOffsetCount == 0,
        "the insertion offset must run to completion on deadline ticks alone; ticks=\(ticks)"
      )
      #expect(
        runLoop.renderer.elidedFrameCount == elidedBefore,
        """
        no frame may elide while a placed-level geometry animation is live; \
        elidedBefore=\(elidedBefore) after=\(runLoop.renderer.elidedFrameCount)
        """
      )
      #expect(
        Self.surfaceContains("slide", terminal),
        """
        the slid-in view must be on the presented raster with no input; last \
        frame was:
        \(terminal.lastSurface?.lines.joined(separator: "\n") ?? "(nothing presented)")
        """
      )
    }
  }

  /// The exit half of the same ownership rule. A departing view with an
  /// offset-only transition leaves the clipped viewport partway through its
  /// curve, at which point its identity drops out of `drawnIdentities` — and
  /// the placed pass that would finish the travel, fire the `.removed`
  /// barrier, and purge the overlay is the pass elision skips. The head tick
  /// deliberately declines to advance a placed-owned removal (it would
  /// double-sample a stateful curve), so an elided frame strands the entry in
  /// `removingNodes` forever: the exit never completes and the 33 ms pump it
  /// keeps re-arming never quiesces.
  @Test("an offset-only removal transition drains instead of stranding off-screen")
  func offsetOnlyRemovalTransitionDrainsOffScreen() async throws {
    let terminalSize = CellSize(width: 20, height: 3)
    let rootIdentity = testIdentity("ElisionSlideRemoval", "Root")
    let terminal = ElisionProbeTerminalHost(surfaceSize: terminalSize)
    let scheduler = FrameScheduler()
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      terminalInputReader: ElisionEmptyInputReader(),
      signalReader: nil,
      scheduler: scheduler,
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(
        invalidationIdentities: [rootIdentity]
      ),
      environmentValues: {
        var values = EnvironmentValues()
        values.terminalAppearance = terminal.appearance
        values.terminalSize = terminalSize
        return values
      }(),
      proposal: .init(width: terminalSize.width, height: terminalSize.height),
      viewBuilder: { _, _ in
        SlideRemovalProbe()
      }
    )
    let clock = VirtualFrameClock(MonotonicInstant.now())
    runLoop.frameClock = { [clock] in clock.now }

    try await withAnimationSinks(runLoop.renderer.internalAnimationController) {
      scheduler.requestInvalidation(of: [rootIdentity])
      var renderedFrames = 0
      try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
      runLoop.renderer.enableSelectiveEvaluation()
      while scheduler.hasPendingFrame(at: clock.now) {
        try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
      }

      let controller = runLoop.renderer.internalAnimationController
      #expect(
        !controller.debugStateSnapshot().removingIdentities.isEmpty,
        "the exit transition must be in flight before the ticks"
      )

      var ticks = 0
      while !controller.debugStateSnapshot().removingIdentities.isEmpty && ticks < 40 {
        scheduler.requestDeadline(clock.advance(by: .milliseconds(16)))
        _ = try await runLoop.renderPendingFramesAsync(
          renderedFrames: &renderedFrames,
          eventPump: nil
        )
        ticks += 1
      }

      #expect(
        controller.debugStateSnapshot().removingIdentities.isEmpty,
        "the exit overlay must drain on deadline ticks alone; ticks=\(ticks)"
      )
      #expect(
        !controller.requiresContinuedAnimationFrames,
        "a drained exit must let the animation pump quiesce"
      )
    }
  }

  private static func surfaceContains(
    _ needle: String,
    _ terminal: ElisionProbeTerminalHost
  ) -> Bool {
    terminal.lastSurface?.lines.contains { $0.contains(needle) } ?? false
  }

  /// Builds a minimal one-shot `FrameHeadTransaction` (no abort checkpoints)
  /// wired to the given live animation controller via a real
  /// `AnimationFrameDraft`. One-shot mode is sufficient here: `commitElided()`
  /// is byte-identical to `commit()` and touches no checkpoint state, and the
  /// load-bearing behavior lives entirely in the animation sub-draft.
  private func makeOneShotFrameHeadTransaction(
    liveController: AnimationController
  ) -> FrameHeadTransaction {
    FrameHeadTransaction(
      viewGraph: ViewGraph(),
      frameState: FrameResolveState(),
      frameInputs: FrameResolveInputBox(),
      graphDraft: ViewGraphFrameDraft(
        liveRegistrations: RuntimeRegistrationSet(),
        checkpoint: nil
      ),
      registrationDraft: FrameHeadRegistrationDraft(),
      presentationPortalDraft: PresentationPortalState().makeDraft(),
      observationDraft: nil,
      animationDraft: liveController.makeFrameDraft(),
      elidedFrameTimingRecorder: ElidedFrameTimingRecorder(),
      frameHeadTimingRecorder: FrameHeadTimingRecorder(),
      checkpoints: nil,
      commitSequence: FrameCommitSequence()
    )
  }
}

private func makeStoredArtifacts(
  identity: Identity,
  placed: PlacedNode,
  semantics: SemanticSnapshot,
  draw: DrawNode
) -> FrameArtifacts {
  FrameArtifacts(
    resolvedTree: ResolvedNode(identity: identity, kind: .root),
    measuredTree: MeasuredNode(
      identity: identity,
      proposal: .unspecified,
      measuredSize: .zero
    ),
    placedTree: placed,
    semanticSnapshot: semantics,
    drawTree: draw,
    rasterSurface: .init(),
    presentationDamage: nil,
    drawnIdentities: [],
    commitPlan: CommitPlan(
      transaction: .init(), semanticSnapshot: semantics, lifecycle: [], handlerInstallations: []),
    diagnostics: .init()
  )
}

private func resolvedLeaf(identity: Identity, opacity: Double) -> ResolvedNode {
  var metadata = DrawMetadata()
  metadata.baseStyle.explicitOpacity = opacity
  return ResolvedNode(
    identity: identity,
    kind: .view("Leaf"),
    drawMetadata: metadata
  )
}

/// A frame-readiness clock that advances past the animation cadence on every
/// read, simulating a machine whose per-frame cost exceeds the 33 ms animation
/// interval regardless of real host speed (the red-pin CI-runner class, report
/// 2026-07-07-008).
@MainActor
private final class SteppingReadinessClock {
  private var reading: MonotonicInstant
  private let step: Duration

  init(start: MonotonicInstant, step: Duration) {
    reading = start
    self.step = step
  }

  func nextReading() -> MonotonicInstant {
    let current = reading
    reading = reading.advanced(by: step)
    return current
  }
}

/// Records which post-injection stages a render executor reached. The
/// off-screen elision short-circuit tests assert every flag stays `false`.
@MainActor
private final class StageReachFlags {
  var latePreference = false
  var fusedFrameTail = false
  var commit = false
}

/// A `repeatForever` chasing-light border pushed far below a 2-row ScrollView
/// viewport, so the animated identity is geometrically clipped out and never
/// reaches `drawnIdentities`. Mirrors the recipe in
/// `AnimationTickVisibilityTests`; the animation is started from `onAppear`.
private struct OffscreenAnimatedProbe: View {
  @State private var phase: Double = 0

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        ForEach(0..<50, id: \.self) { _ in
          Text("filler")
        }
        Text("chasing")
          .padding(1)
          .frame(width: 10, height: 3)
          .border(
            blend: BorderBlend([.red, .yellow, .green, .cyan, .blue, .red]),
            set: .single,
            phase: phase
          )
      }
    }
    .frame(width: 20, height: 2)
    .onAppear {
      withAnimation(
        .linear(duration: .milliseconds(3000))
          .repeatForever(autoreverses: false)
      ) {
        phase = 1.0
      }
    }
  }
}

/// Mirror of ``OffscreenAnimatedProbe`` but with a FINITE animation that
/// carries a `withAnimation { … } completion: { … }` closure. The animated
/// border sits far below a 2-row ScrollView viewport, so it is clipped out and
/// never reaches `drawnIdentities`; the deadline ticks carrying its completion
/// therefore elide. The completion increments the injected counter when the
/// finite animation reaches its final value.
private struct OffscreenCompletingProbe: View {
  let completion: FireCounter
  @State private var phase: Double = 0

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        ForEach(0..<50, id: \.self) { _ in
          Text("filler")
        }
        Text("chasing")
          .padding(1)
          .frame(width: 10, height: 3)
          .border(
            blend: BorderBlend([.red, .yellow, .green, .cyan, .blue, .red]),
            set: .single,
            phase: phase
          )
      }
    }
    .frame(width: 20, height: 2)
    .onAppear {
      withAnimation(.linear(duration: .milliseconds(80))) {
        phase = 1.0
      } completion: {
        completion.increment()
      }
    }
  }
}

/// An off-screen view whose `frameHeight` is animated by `withAnimation` — a
/// LAYOUT-affecting animation, not the paint-only `borderBlendPhase` every
/// other probe drives. The animated `.frame(height:)` sits far below a 2-row
/// ScrollView viewport, so its painted bounds never intersect the viewport and
/// the identity is never recorded in `drawnIdentities`. The height oscillates
/// perpetually via `repeatForever` so the layout animation stays in flight
/// across the deadline ticks the test drives.
private struct OffscreenLayoutAnimatedProbe: View {
  @State private var boxHeight: Int = 3

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        ForEach(0..<50, id: \.self) { _ in
          Text("filler")
        }
        // The animated slot: `.frame(height:)` lowers to a `.frame`
        // layoutBehavior whose height is captured into AnimatableSlot
        // `.frameHeight`. Animating `boxHeight` therefore drives a
        // layout-affecting property animation through applyInterpolations'
        // `.property` path.
        Text("grow")
          .frame(width: 10, height: boxHeight)
      }
    }
    .frame(width: 20, height: 2)
    .onAppear {
      withAnimation(
        .linear(duration: .milliseconds(3000))
          .repeatForever(autoreverses: true)
      ) {
        boxHeight = 8
      }
    }
  }
}

/// A `repeatForever` chasing-light border placed INSIDE a tall ScrollView
/// viewport, so the animated identity is visible and IS present in
/// `drawnIdentities`. Mirrors the visible case in `AnimationTickVisibilityTests`
/// so its deadline-only ticks must NOT elide.
private struct OnScreenAnimatedProbe: View {
  @State private var phase: Double = 0

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        Text("chasing")
          .padding(1)
          .frame(width: 10, height: 3)
          .border(
            blend: BorderBlend([.red, .yellow, .green, .cyan, .blue, .red]),
            set: .single,
            phase: phase
          )
      }
    }
    .frame(width: 20, height: 20)
    .onAppear {
      withAnimation(
        .linear(duration: .milliseconds(3000))
          .repeatForever(autoreverses: false)
      ) {
        phase = 1.0
      }
    }
  }
}

/// Sequences a removal transition and an off-screen elision source onto
/// SEPARATE frames so the two animations never share a single animation
/// transaction (which would conflate their animation boxes).
///
/// Timeline:
///   1. Mount: an ON-SCREEN panel (top of a 2-row viewport) is visible; the
///      off-screen border is not yet present.
///   2. The panel's `onAppear` animates its own removal via
///      `.transition(.opacity)` with a finite `withAnimation`. It is the only
///      animation registered on THAT frame, so its box is unambiguous. While it
///      drains the panel identity is on-screen, so those frames render and
///      present (no elision). The schedule is spent in virtual time — the test
///      drives it a step per tick.
///   3. Flipping `showPanel` also swaps in the off-screen
///      `InterleavedOffscreenBorder` (clipped far below the viewport), whose own
///      `onAppear` — firing on a LATER frame than the removal, which is what
///      keeps the two transactions separate — starts a perpetual `repeatForever`
///      phase animation whose deadline ticks elide. It is therefore already live
///      while the removal is still draining; the removal's identity is what
///      keeps those frames rendering until its overlay is purged.
///
/// Asserts that skipping `capturePlacedTree` on the post-removal elided frames
/// did not corrupt the removal/placed-tree bookkeeping: the removal completes
/// and the off-screen ticks then elide on the surviving graph.
private struct InterleavedRemovalProbe: View {
  @State private var showPanel: Bool = true

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        if showPanel {
          Text("panel")
            .id(testIdentity("InterleaveRemovalPanel"))
            .transition(.opacity)
        } else {
          ForEach(0..<50, id: \.self) { _ in
            Text("filler")
          }
          InterleavedOffscreenBorder()
        }
      }
    }
    .frame(width: 20, height: 2)
    .onAppear {
      withAnimation(.linear(duration: .milliseconds(80))) {
        showPanel = false
      }
    }
  }
}

/// Off-screen chasing-light border (rendered only after the removal completes,
/// clipped below the 2-row viewport) driving a perpetual `repeatForever` phase
/// animation. Its `onAppear` fires on a frame distinct from the removal, so the
/// two animations never share an animation transaction.
private struct InterleavedOffscreenBorder: View {
  @State private var phase: Double = 0

  var body: some View {
    Text("chasing")
      .padding(1)
      .frame(width: 10, height: 3)
      .border(
        blend: BorderBlend([.red, .yellow, .green, .cyan, .blue, .red]),
        set: .single,
        phase: phase
      )
      .onAppear {
        withAnimation(
          .linear(duration: .milliseconds(3000))
            .repeatForever(autoreverses: false)
        ) {
          phase = 1.0
        }
      }
  }
}

private final class ElisionProbeTerminalHost: PresentationSurface {
  private(set) var surfaceSize: CellSize
  let capabilityProfile: TerminalCapabilityProfile = .previewUnicode
  let appearance: TerminalAppearance = .fallback
  private(set) var presentCount = 0
  /// The most recent presented raster, so a test can assert on what the user
  /// would actually be looking at rather than only on frame counts.
  private(set) var lastSurface: RasterSurface?

  init(surfaceSize: CellSize) {
    self.surfaceSize = surfaceSize
  }

  /// Mirrors a hosted transport's resize (`updateSurfaceSize` + SIGWINCH)
  /// after the wake was consumed: the size changes with no scheduler cause
  /// left behind, exactly the state a skipped SIGWINCH frame leaves.
  func updateSurfaceSize(_ size: CellSize) {
    surfaceSize = size
  }

  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func clearScreen() throws {}
  func moveCursor(to _: CellPoint) throws {}
  func write(_: String) throws {}

  @discardableResult
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    presentCount += 1
    lastSurface = surface
    return .init(
      bytesWritten: 0,
      linesTouched: surface.size.height,
      cellsChanged: surface.size.width * surface.size.height,
      strategy: .fullRepaint
    )
  }
}

private final class ElisionEmptyInputReader: TerminalInputReading {
  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }
}

/// Slides a view in on appear with an offset-only transition, inside a clipping
/// viewport — the gallery's shape, and the one that deadlocks.
///
/// `.slide` carries no opacity effect, so the insertion registers ONLY an
/// `.insertionOffset` animation: the placed-level scope whose evaluation an
/// elided frame skips. The clip is load-bearing for the repro. A node merely
/// past the surface edge is still recorded in `drawnIdentities`, so its ticks
/// stay non-disjoint and render anyway; a node clipped out by a viewport is
/// correctly withheld from that set, which is what lets the gate mistake "has
/// never been drawn" for "can never be drawn".
private struct SlideInsertionProbe: View {
  @State private var show = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("anchor")
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          if show {
            Text("slide").transition(.slide)
          }
        }
      }
      .frame(width: 20, height: 1, alignment: .topLeading)
    }
    .frame(width: 20, height: 3, alignment: .topLeading)
    .onAppear {
      withAnimation(.linear(duration: .milliseconds(300))) {
        show = true
      }
    }
  }
}

/// Slides a view out on appear with an offset-only transition, inside a
/// clipping viewport: the exit counterpart of ``SlideInsertionProbe``. The
/// departing overlay leaves the viewport partway through its curve, dropping
/// its identity out of `drawnIdentities` while the placed pass still owes it
/// a completion and a purge.
private struct SlideRemovalProbe: View {
  @State private var show = true

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("anchor")
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          if show {
            Text("slide").transition(.slide)
          }
        }
      }
      .frame(width: 20, height: 1, alignment: .topLeading)
    }
    .frame(width: 20, height: 3, alignment: .topLeading)
    .onAppear {
      withAnimation(.linear(duration: .milliseconds(300))) {
        show = false
      }
    }
  }
}
