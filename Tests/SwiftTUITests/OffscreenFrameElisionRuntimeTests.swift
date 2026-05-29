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
    retainedState.storeCommittedFrame(artifacts, baselinePlacedTree: placed)
    #expect(retainedState.previousDrawnIdentities == expected)
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
        latePreferenceReconciliation: { _, _ in
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
      handlers: AsyncRenderStageHandlers(
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

    AnimationRegistrationStorage.currentSink = runLoop.renderer.internalAnimationController
    TransitionRegistrationStorage.currentSink = runLoop.renderer.internalAnimationController
    AnimationCompletionStorage.currentSink = runLoop.renderer.internalAnimationController
    defer {
      AnimationRegistrationStorage.currentSink = nil
      TransitionRegistrationStorage.currentSink = nil
      AnimationCompletionStorage.currentSink = nil
    }

    // Mount the tree (and run the onAppear-triggered follow-up) so the
    // repeatForever animation is in flight and the off-screen border has been
    // committed once (clipped, so it is absent from previousDrawnIdentities).
    scheduler.requestInvalidation(of: [rootIdentity])
    var renderedFrames = 0
    _ = try await runLoop.renderPendingFramesAsync(
      renderedFrames: &renderedFrames,
      eventPump: nil
    )
    runLoop.renderer.enableSelectiveEvaluation()
    while scheduler.hasPendingFrame(at: .now()) {
      _ = try await runLoop.renderPendingFramesAsync(
        renderedFrames: &renderedFrames,
        eventPump: nil
      )
    }

    #expect(
      runLoop.renderer.internalAnimationController.activeAnimationCount > 0,
      "the off-screen repeatForever animation must be in flight before the deadline tick"
    )
    let elidedBefore = runLoop.renderer.elidedFrameCount
    let presentsBefore = terminal.presentCount

    // Drive a pure animation-deadline frame: this is the case the gate elides.
    scheduler.requestDeadline(.now())
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
    // scheduled the next animation deadline.
    #expect(
      scheduler.hasPendingFrame(at: .now().advanced(by: .milliseconds(100))),
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

    AnimationRegistrationStorage.currentSink = runLoop.renderer.internalAnimationController
    TransitionRegistrationStorage.currentSink = runLoop.renderer.internalAnimationController
    AnimationCompletionStorage.currentSink = runLoop.renderer.internalAnimationController
    defer {
      AnimationRegistrationStorage.currentSink = nil
      TransitionRegistrationStorage.currentSink = nil
      AnimationCompletionStorage.currentSink = nil
    }

    // Mount + run the onAppear follow-up so the finite off-screen animation is
    // in flight and the clipped border has committed once (absent from
    // previousDrawnIdentities).
    scheduler.requestInvalidation(of: [rootIdentity])
    var renderedFrames = 0
    _ = try await runLoop.renderPendingFramesAsync(
      renderedFrames: &renderedFrames,
      eventPump: nil
    )
    runLoop.renderer.enableSelectiveEvaluation()
    while scheduler.hasPendingFrame(at: .now()) {
      _ = try await runLoop.renderPendingFramesAsync(
        renderedFrames: &renderedFrames,
        eventPump: nil
      )
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

    // Drive deadline-only tick frames until the finite animation's real-time
    // schedule elapses and the completion fires. The injection stamps every
    // frame with MonotonicInstant.now(), so the curve returns nil once the
    // 80 ms duration has passed; the carrier tick is off-screen-only, so it
    // elides instead of presenting. Bounded by an iteration cap — never a
    // wall-clock sleep — so a hung completion fails the test fast.
    var ticks = 0
    let maxTicks = 400
    while completion.count == 0 && ticks < maxTicks {
      scheduler.requestDeadline(.now())
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

  // MARK: - Oracle soundness (Task 8.2)

  /// Guards the §5.3 soundness assumption that `redrawIdentities` is the
  /// authoritative overlap oracle: a deadline-only tick whose redraw set
  /// OVERLAPS the visible `drawnIdentities` must NOT be elided — it renders and
  /// presents.
  ///
  /// Construction note: I could not build an OFF-SCREEN animation that forces an
  /// ON-SCREEN sibling to redraw. SwiftTUI's clip walk geometrically isolates a
  /// view below a ScrollView viewport from its visible siblings, and
  /// `applyInterpolations` only inserts the directly-animated identity into
  /// `redrawIdentities` (see AnimationController.applyInterpolations, the
  /// `.property` case). A purely off-screen animated property therefore cannot
  /// produce a redraw set that overlaps a visible identity through this
  /// framework's layout model — the clipping fully isolates them, which is
  /// precisely why eliding it is sound. So this test takes the closest
  /// meaningful form the task authorizes: an ON-SCREEN animation whose tick
  /// redraw set overlaps `drawnIdentities` must NOT elide. This directly
  /// exercises the gate's disjointness branch in the failing-to-elide
  /// direction — if the oracle ever wrongly reported disjointness for a visible
  /// animation, this frame would silently stop presenting.
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

    AnimationRegistrationStorage.currentSink = runLoop.renderer.internalAnimationController
    TransitionRegistrationStorage.currentSink = runLoop.renderer.internalAnimationController
    AnimationCompletionStorage.currentSink = runLoop.renderer.internalAnimationController
    defer {
      AnimationRegistrationStorage.currentSink = nil
      TransitionRegistrationStorage.currentSink = nil
      AnimationCompletionStorage.currentSink = nil
    }

    scheduler.requestInvalidation(of: [rootIdentity])
    var renderedFrames = 0
    _ = try await runLoop.renderPendingFramesAsync(
      renderedFrames: &renderedFrames,
      eventPump: nil
    )
    runLoop.renderer.enableSelectiveEvaluation()
    while scheduler.hasPendingFrame(at: .now()) {
      _ = try await runLoop.renderPendingFramesAsync(
        renderedFrames: &renderedFrames,
        eventPump: nil
      )
    }

    #expect(
      runLoop.renderer.internalAnimationController.activeAnimationCount > 0,
      "the on-screen repeatForever animation must be in flight before the deadline tick"
    )

    let elidedBefore = runLoop.renderer.elidedFrameCount
    let presentsBefore = terminal.presentCount

    // Drive a pure animation-deadline frame. The animated border is INSIDE the
    // viewport, so the tick's redrawIdentities overlap drawnIdentities; the gate
    // must therefore NOT fire.
    scheduler.requestDeadline(.now())
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

    AnimationRegistrationStorage.currentSink = runLoop.renderer.internalAnimationController
    TransitionRegistrationStorage.currentSink = runLoop.renderer.internalAnimationController
    AnimationCompletionStorage.currentSink = runLoop.renderer.internalAnimationController
    defer {
      AnimationRegistrationStorage.currentSink = nil
      TransitionRegistrationStorage.currentSink = nil
      AnimationCompletionStorage.currentSink = nil
    }

    // Mount + the onAppear-triggered follow-up frame: the panel's removal
    // transition starts. The off-screen border has not yet appeared (it is
    // gated behind `!showPanel`), so the only animation in flight is the
    // unambiguous finite removal.
    scheduler.requestInvalidation(of: [rootIdentity])
    var renderedFrames = 0
    _ = try await runLoop.renderPendingFramesAsync(
      renderedFrames: &renderedFrames,
      eventPump: nil
    )
    let controller = runLoop.renderer.internalAnimationController
    runLoop.renderer.enableSelectiveEvaluation()

    #expect(
      !controller.debugStateSnapshot().removingIdentities.isEmpty,
      "the on-screen removal transition must be in flight before the interleaving"
    )

    // Phase 1: drive deadline ticks until the removal transition has fully
    // drained (its overlay purged). While the removal is in flight its identity
    // is on-screen and in the tick's redrawIdentities, so those frames render
    // and present — they do NOT elide. Bounded by an iteration cap so a stuck
    // removal fails fast rather than hanging.
    var ticks = 0
    let maxTicks = 400
    while !controller.debugStateSnapshot().removingIdentities.isEmpty && ticks < maxTicks {
      scheduler.requestDeadline(.now())
      _ = try await runLoop.renderPendingFramesAsync(
        renderedFrames: &renderedFrames,
        eventPump: nil
      )
      ticks += 1
    }

    // The removal must have drained — no crash, overlay purged.
    #expect(
      controller.debugStateSnapshot().removingIdentities.isEmpty,
      "the removal overlay must drain to completion; ticks=\(ticks)"
    )

    // The off-screen border now appears (it was gated behind `!showPanel`); run
    // any pending follow-up frames so its onAppear starts the repeatForever
    // animation on a frame distinct from the removal.
    while scheduler.hasPendingFrame(at: .now()) && ticks < maxTicks {
      _ = try await runLoop.renderPendingFramesAsync(
        renderedFrames: &renderedFrames,
        eventPump: nil
      )
      ticks += 1
    }
    #expect(
      controller.activeAnimationCount > 0,
      "the off-screen repeatForever border must be in flight after the removal drains"
    )

    // Phase 2: now that the removal has drained on the surviving graph, the
    // off-screen border's deadline ticks must elide — proving the reduced-commit
    // path (capturePlacedTree skipped) left the post-removal placed-tree
    // bookkeeping intact.
    let elidedBefore = runLoop.renderer.elidedFrameCount
    while runLoop.renderer.elidedFrameCount == elidedBefore && ticks < maxTicks {
      scheduler.requestDeadline(.now())
      _ = try await runLoop.renderPendingFramesAsync(
        renderedFrames: &renderedFrames,
        eventPump: nil
      )
      ticks += 1
    }
    #expect(
      runLoop.renderer.elidedFrameCount > elidedBefore,
      """
      off-screen ticks must elide on the post-removal graph; \
      elidedBefore=\(elidedBefore) after=\(runLoop.renderer.elidedFrameCount) ticks=\(ticks)
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
      checkpoints: nil
    )
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
///      `.transition(.opacity)` with a finite `withAnimation`. This is the only
///      animation in flight, so its box is unambiguous and the removal drains
///      cleanly on its real-time schedule. While it drains the panel identity is
///      on-screen, so those frames render and present (no elision).
///   3. Once the panel is gone, the off-screen `InterleavedOffscreenBorder`
///      conditionally appears (clipped far below the viewport). Its own
///      `onAppear` — firing on a later frame — starts a perpetual `repeatForever`
///      phase animation whose deadline ticks elide.
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
  let surfaceSize: CellSize
  let capabilityProfile: TerminalCapabilityProfile = .previewUnicode
  let appearance: TerminalAppearance = .fallback
  private(set) var presentCount = 0

  init(surfaceSize: CellSize) {
    self.surfaceSize = surfaceSize
  }

  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func clearScreen() throws {}
  func moveCursor(to _: CellPoint) throws {}
  func write(_: String) throws {}

  @discardableResult
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    presentCount += 1
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
