import SwiftTUICore
import SwiftTUIViews

struct FrameTailCancellationStrategy: Sendable {
  var awaitQueuedCancellationSignal: @MainActor @Sendable () async -> Void
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
      // unreadable. Off in release by default → false → policy-only behavior.
      verifyIncrementalRasterDamage: SoundnessProbeConfiguration.isSampledFrame,
      clock: draft.clock
    )
    recordIncrementalRasterMismatchIfCaught(tail.incrementalMismatch)
    return tail
  }

  /// F06: the incremental-vs-fresh oracle historically repaired mismatches in
  /// silence, so incomplete-damage producer bugs shipped as release-only
  /// corruption while every DEBUG run self-healed. This is the first main-actor
  /// point after the (possibly off-main) raster tail returns — record every
  /// caught mismatch on the probe's counters here.
  @MainActor
  private func recordIncrementalRasterMismatchIfCaught(
    _ mismatch: Rasterizer.IncrementalRasterMismatch?
  ) {
    guard let mismatch else {
      return
    }
    SoundnessProbeConfiguration.recordRasterDamageMismatch(
      mismatch.mismatchedRows.isEmpty
        ? "incremental raster mismatch: non-cell surface state diverged from fresh raster"
        : "incremental raster mismatch: rows \(mismatch.mismatchedRows) diverged from fresh raster"
    )
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

      @MainActor
      func waitForQueuedCancellationSignal() async -> FrameTailJobState {
        await cancellation.awaitQueuedCancellationSignal()
        if !Task.isCancelled,
          await cancellation.shouldCancelQueued(),
          cancellationToken.cancelBeforeStart()
        {
          layoutTask.cancel()
          return .cancelledBeforeStart
        }
        return await cancellationToken.waitUntilLeavesQueue()
      }

      let queueExitState = await withTaskGroup(of: FrameTailJobState.self) { group in
        group.addTask {
          await cancellationToken.waitUntilLeavesQueue()
        }
        group.addTask {
          await waitForQueuedCancellationSignal()
        }
        let state = await group.next() ?? cancellationToken.currentState
        group.cancelAll()
        return state
      }

      if queueExitState == .cancelledBeforeStart {
        layoutTask.cancel()
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
    recordIncrementalRasterMismatchIfCaught(tail.incrementalMismatch)
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
