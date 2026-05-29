import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
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
