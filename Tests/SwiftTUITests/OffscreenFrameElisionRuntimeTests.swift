import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@Suite("OffscreenFrameElisionRuntime")
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

  /// When `elideIfOffscreen` fires right after animation injection, the
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
        elideIfOffscreen: { _ in true },
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
        elideIfOffscreen: { _ in true },
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
