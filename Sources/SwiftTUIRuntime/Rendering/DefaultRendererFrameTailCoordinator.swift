import SwiftTUICore
import SwiftTUIViews

struct FrameTailCancellationStrategy: Sendable {
  /// Awaits the host's queued-cancellation signal. Implementations must
  /// return when the passed release trips (the queued job left the queue),
  /// not only when their own signal fires: the coordinator awaits this
  /// inline and never cancels a task to abandon it (entry 14).
  var awaitQueuedCancellationSignal:
    @MainActor @Sendable (any PendingFrameWaitReleasing) async -> Void
  var shouldCancelQueued: @MainActor @Sendable () async -> Bool
}

enum FrameTailLayoutStageResult {
  case output(AsyncFrameTailLayoutStageOutput, cancellationToken: FrameTailJobCancellationToken?)
  case cancelledBeforeStart
}

/// Coordinates the renderer stages that run after frame-head preparation and
/// before commit.
///
/// `DefaultRenderer` still owns the live graph, frame-head transaction, and
/// commit side effects. This helper owns only the frame-tail sequencing:
/// late-preference reconciliation, layout cancellation, animation overlay
/// sampling, and raster handoff.
struct DefaultRendererFrameTailCoordinator: Sendable {
  var frameTailRenderer: FrameTailRenderer
  var latePreferenceReconciliationPolicy: LatePreferenceReconciliationPolicy

  /// Shared fused-frame-tail head: captures the baseline placed tree for the
  /// animation controller and snapshots any pending placed-level animation
  /// overlays.
  ///
  /// Both the synchronous (`renderFusedFrameTail`) and asynchronous
  /// (`renderFrameTailRasterStage`) tail strategies run exactly this work before
  /// they diverge: the sync path calls `renderRaster`, and the async path calls
  /// `renderRasterAsync`.
  ///
  /// Capture the baseline placed tree, before overlays, for two reasons:
  /// 1. The animation controller's removal-snapshot lookup on the next frame.
  /// 2. The retained-layout store, which must cache canonical layout rather
  ///    than animation-decorated transient nodes.
  @MainActor
  private func prepareAnimationOverlaySnapshot(
    draft: FrameHeadDraft,
    layout: FrameTailLayoutOutput
  ) -> (placed: PlacedNode, overlay: PlacedAnimationOverlaySnapshot) {
    let placed = layout.baselinePlaced
    let animationController = draft.animationDraft.controller
    animationController.capturePlacedTree(layout.baselinePlaced)
    let animationOverlaySnapshot = animationController.placedAnimationOverlaySnapshot(
      for: placed,
      at: draft.animationTimestamp,
      surfaceSize: animationSurfaceSize(for: draft.frameTailInput.proposal)
    )
    return (placed, animationOverlaySnapshot)
  }

  @MainActor
  func renderFusedFrameTail(
    draft: FrameHeadDraft,
    reconciledTailLayout: ReconciledFrameTailLayout
  ) -> FrameTailOutput {
    let layout = reconciledTailLayout.layout
    let (placed, animationOverlaySnapshot) = prepareAnimationOverlaySnapshot(
      draft: draft,
      layout: layout
    )
    let tail = frameTailRenderer.renderRaster(
      reconciledTailLayout.input,
      layout: layout,
      placed: placed,
      animationOverlaySnapshot: animationOverlaySnapshot,
      // Latch the soundness probe's per-frame sampling decision here on the main
      // actor; the raster tail may run off-main, where this @MainActor state is
      // unreadable. False on release's unsampled frames → policy-only behavior.
      verifyIncrementalRasterDamage: SoundnessProbeConfiguration.isSampledFrame,
      clock: draft.clock
    )
    Self.recordIncrementalRasterMismatchIfCaught(tail.incrementalMismatch)
    return tail
  }

  /// F06: the incremental-vs-fresh oracle historically repaired mismatches in
  /// silence, so incomplete-damage producer bugs shipped as release-only
  /// corruption while every DEBUG run self-healed. This is the first main-actor
  /// point after the (possibly off-main) raster tail returns — record every
  /// caught mismatch on the probe's counters here.
  @MainActor
  package static func recordIncrementalRasterMismatchIfCaught(
    _ mismatch: Rasterizer.IncrementalRasterMismatch?
  ) {
    guard let mismatch else {
      return
    }
    let detail =
      mismatch.mismatchedRows.isEmpty
      ? "incremental raster mismatch: non-cell surface state diverged from fresh raster"
      : "incremental raster mismatch: rows \(mismatch.mismatchedRows) diverged from fresh raster"
    SoundnessProbeConfiguration.recordRasterDamageMismatch(detail)
    // The 2026-07-28 full-gate census observed zero unexpected mismatches.
    // Record first so the release trace and crash diagnostics retain context.
    #if DEBUG
      if SoundnessProbeConfiguration.isEnabled {
        assertionFailure(detail)
      }
    #endif
  }

  @MainActor
  func renderLayoutResolvingLatePreferences(
    _ initialInput: FrameTailInput,
    clock: ContinuousClock?
  ) -> ReconciledFrameTailLayout {
    LatePreferenceReconciliationStage(
      policy: latePreferenceReconciliationPolicy
    ).run(initialInput: initialInput) { input in
      frameTailRenderer.renderLayout(
        input,
        clock: clock
      )
    }
  }

  @MainActor
  func renderFrameTailDraft(
    _ draft: FrameHeadDraft
  ) async -> AsyncFrameTailDraftOutput {
    let layoutResult = await renderFrameTailLayoutStage(draft)
    guard case .output(let layoutStage, _) = layoutResult else {
      preconditionFailure("Non-cancellable frame tail unexpectedly cancelled.")
    }
    return await renderFrameTailRasterStage(
      draft: draft,
      layoutStage: layoutStage
    )
  }

  @MainActor
  func renderFrameTailLayoutStage(
    _ draft: FrameHeadDraft,
    cancellation: FrameTailCancellationStrategy? = nil
  ) async -> FrameTailLayoutStageResult {
    if let cancellation {
      let cancellationToken = FrameTailJobCancellationToken()
      let layoutTask = Task { @MainActor in
        await renderLayoutResolvingLatePreferencesAsync(
          draft,
          cancellationToken: cancellationToken
        )
      }

      // No task is ever cancelled on this seam (entry 14): a cancel landing
      // concurrently with a task's first schedule or resume-enqueue can lose
      // the wakeup inside the concurrency runtime, freezing the main actor
      // with every thread idle. The signal wait runs inline and is released
      // by the token's queue exit instead of by `group.cancelAll()`, and a
      // cancelled-before-start layout job bails at worker entry
      // (`markStarted` returns false), so `layoutTask` needs no cancel
      // either — it drains on its own.
      await cancellation.awaitQueuedCancellationSignal(cancellationToken)
      if !Task.isCancelled,
        await cancellation.shouldCancelQueued(),
        cancellationToken.cancelBeforeStart()
      {
        return .cancelledBeforeStart
      }

      let queueExitState = await cancellationToken.waitUntilLeavesQueue()
      if queueExitState == .cancelledBeforeStart {
        return .cancelledBeforeStart
      }

      let layoutResult = await layoutTask.value
      guard let reconciledLayout = layoutResult.layout else {
        return .cancelledBeforeStart
      }
      return .output(
        AsyncFrameTailLayoutStageOutput(
          frameTailInput: reconciledLayout.input,
          layout: reconciledLayout.layout,
          resolved: reconciledLayout.resolved,
          runtimeIssues: reconciledLayout.runtimeIssues,
          suspensionDuration: layoutResult.suspensionDuration
        ),
        cancellationToken: cancellationToken
      )
    }

    if frameTailRenderer.canOffloadLayout(draft.frameTailInput) {
      let layoutPass = await renderFrameTailLayoutAsync(
        draft.frameTailInput,
        clock: draft.clock,
        cancellationToken: nil
      )
      guard let layout = layoutPass.layout else {
        return .cancelledBeforeStart
      }
      return .output(
        AsyncFrameTailLayoutStageOutput(
          frameTailInput: draft.frameTailInput,
          layout: layout,
          resolved: draft.resolved,
          runtimeIssues: layoutRuntimeIssues(input: draft.frameTailInput, resolved: draft.resolved),
          suspensionDuration: layoutPass.suspensionDuration
        ),
        cancellationToken: nil
      )
    }

    let layoutResult = await renderLayoutResolvingLatePreferencesAsync(
      draft,
      cancellationToken: nil
    )
    guard let reconciledLayout = layoutResult.layout else {
      return .cancelledBeforeStart
    }
    return .output(
      AsyncFrameTailLayoutStageOutput(
        frameTailInput: reconciledLayout.input,
        layout: reconciledLayout.layout,
        resolved: reconciledLayout.resolved,
        runtimeIssues: reconciledLayout.runtimeIssues,
        suspensionDuration: layoutResult.suspensionDuration
      ),
      cancellationToken: nil
    )
  }

  @MainActor
  func renderFrameTailRasterStage(
    draft: FrameHeadDraft,
    layoutStage: AsyncFrameTailLayoutStageOutput,
    completionToken: FrameTailJobCancellationToken? = nil
  ) async -> AsyncFrameTailDraftOutput {
    let layout = layoutStage.layout
    let (placed, animationOverlaySnapshot) = prepareAnimationOverlaySnapshot(
      draft: draft,
      layout: layout
    )
    let suspensionHooks = frameTailRenderer.renderSuspensionHooksSnapshot()
    let rasterSuspensionStart = draft.clock?.now
    suspensionHooks?.onBegin?()
    let tail = await frameTailRenderer.renderRasterAsync(
      layoutStage.frameTailInput,
      layout: layout,
      placed: placed,
      animationOverlaySnapshot: animationOverlaySnapshot,
      // Latch the probe's sampling decision on the main actor before the raster
      // tail is offloaded to the worker (see the sync path above).
      verifyIncrementalRasterDamage: SoundnessProbeConfiguration.isSampledFrame,
      clock: draft.clock
    )
    suspensionHooks?.onEnd?()
    Self.recordIncrementalRasterMismatchIfCaught(tail.incrementalMismatch)
    let rasterSuspensionDuration =
      if let rasterSuspensionStart, let clock = draft.clock {
        rasterSuspensionStart.duration(to: clock.now)
      } else {
        Duration.zero
      }

    let output = AsyncFrameTailDraftOutput(
      frameTailInput: layoutStage.frameTailInput,
      layout: layout,
      tail: tail,
      resolved: layoutStage.resolved,
      runtimeIssues: layoutStage.runtimeIssues,
      renderSuspensionDuration: layoutStage.suspensionDuration + rasterSuspensionDuration
    )
    completionToken?.markCompleted()
    return output
  }

  @MainActor
  private func renderLayoutResolvingLatePreferencesAsync(
    _ draft: FrameHeadDraft,
    cancellationToken: FrameTailJobCancellationToken?
  ) async -> AsyncLatePreferenceReconciliationOutput {
    guard frameTailRenderer.needsPreparedGraphDuringLayout(draft.frameTailInput) else {
      return await renderLayoutResolvingLatePreferencesAsync(
        draft.frameTailInput,
        clock: draft.clock,
        cancellationToken: cancellationToken
      )
    }

    // Claim the job before touching the head. The layout task is never
    // cancelled (entry 14), so its first slot can land after the coordinator
    // took cancelled-before-start and the caller discarded this head —
    // materializing then would revive a spent transaction, and a cancel
    // landing after materialize would discard the head out from under the
    // suspend in the defer below. markStarted is atomic with
    // cancelBeforeStart on the token, so claiming first makes the cancel
    // impossible and losing the claim means the head must not be touched.
    // The worker-entry markStarted stays correct as a second call
    // (already-started reports true).
    if let cancellationToken, !cancellationToken.markStarted() {
      return AsyncLatePreferenceReconciliationOutput(
        layout: nil,
        suspensionDuration: .zero
      )
    }

    draft.transaction.materializePreparedState()
    defer {
      draft.transaction.suspendPreparedState()
    }
    let layoutResult = await renderLayoutResolvingLatePreferencesAsync(
      draft.frameTailInput,
      clock: draft.clock,
      cancellationToken: cancellationToken
    )
    if layoutResult.layout != nil {
      draft.transaction.recordPreparedGraphState()
    }
    return layoutResult
  }

  @MainActor
  private func renderLayoutResolvingLatePreferencesAsync(
    _ initialInput: FrameTailInput,
    clock: ContinuousClock?,
    cancellationToken: FrameTailJobCancellationToken?
  ) async -> AsyncLatePreferenceReconciliationOutput {
    await LatePreferenceReconciliationStage(
      policy: latePreferenceReconciliationPolicy
    ).runAsync(
      initialInput: initialInput,
      shouldRelayoutLayoutRealizationSnapshot: { input in
        frameTailRenderer.canOffloadLayout(input)
      }
    ) { input in
      await renderFrameTailLayoutAsync(
        input,
        clock: clock,
        cancellationToken: cancellationToken
      )
    }
  }

  @MainActor
  private func renderFrameTailLayoutAsync(
    _ input: FrameTailInput,
    clock: ContinuousClock?,
    cancellationToken: FrameTailJobCancellationToken?
  ) async -> AsyncFrameTailLayoutPass {
    let suspensionHooks = frameTailRenderer.renderSuspensionHooksSnapshot()
    let layoutSuspends = frameTailRenderer.canOffloadLayout(input)
    let layoutSuspensionStart = layoutSuspends ? clock?.now : nil
    if layoutSuspends {
      suspensionHooks?.onBegin?()
    }
    let layout = await frameTailRenderer.renderLayoutAsync(
      input,
      clock: clock,
      cancellationToken: cancellationToken
    )
    if layoutSuspends {
      suspensionHooks?.onEnd?()
    }
    let layoutSuspensionDuration =
      if let layoutSuspensionStart, let clock {
        layoutSuspensionStart.duration(to: clock.now)
      } else {
        Duration.zero
      }
    return AsyncFrameTailLayoutPass(
      layout: layout,
      suspensionDuration: layoutSuspensionDuration
    )
  }
}

private func animationSurfaceSize(for proposal: ProposedSize) -> CellSize? {
  guard
    case .finite(let width) = proposal.width,
    case .finite(let height) = proposal.height
  else {
    return nil
  }

  return CellSize(width: max(0, width), height: max(0, height))
}
